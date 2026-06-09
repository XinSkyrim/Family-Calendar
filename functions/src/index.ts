/* eslint-disable */
import * as fs from "fs";
import * as os from "os";
import * as path from "path";
import {execFile} from "child_process";
import {promisify} from "util";
import OpenAI from "openai";
import {setGlobalOptions} from "firebase-functions/v2";
import {onDocumentCreated} from "firebase-functions/v2/firestore";
import {onCall, HttpsError} from "firebase-functions/v2/https";
import {defineSecret} from "firebase-functions/params";
import * as logger from "firebase-functions/logger";
import {initializeApp} from "firebase-admin/app";
import {FieldValue, getFirestore} from "firebase-admin/firestore";
import {getStorage} from "firebase-admin/storage";
import ffmpegInstaller from "@ffmpeg-installer/ffmpeg";

initializeApp();
setGlobalOptions({maxInstances: 10});

const openAiKeySecret = defineSecret("OPENAI_API_KEY");
const DEFAULT_MODEL = process.env.OPENAI_MODEL || "gpt-4o-mini";
const DEFAULT_TIMEZONE = "Australia/Adelaide";
const MAX_SUMMARY_CHARS = 150;
const REALTIME_TRANSCRIBE_MODEL = "gpt-realtime-whisper";
const REALTIME_TRANSCRIBE_SAMPLE_RATE = 24000;
const RECORDING_TRANSCRIBE_MODEL = "gpt-4o-mini-transcribe";
const RECORDING_SUMMARY_MODEL = "gpt-4o-mini";
const MAX_TRANSCRIPTION_FILE_BYTES = 24 * 1024 * 1024;
const AUDIO_SEGMENT_SECONDS = 20 * 60;
const NO_RECOGNIZED_INFO =
  "I couldn't identify enough meaningful speech to summarize this voice note. Please try recording again a little closer to the microphone, or add notes manually.";
const execFileAsync = promisify(execFile);

interface DraftEvent {
  title: string;
  startISO?: string;
  endISO?: string;
  dateISO?: string;
  timeISO?: string;
  timezone?: string;
  participants?: string[];
  location?: string;
  notes?: string;
  confidence?: number;
}

interface ChatWithAIRequest {
  message?: unknown;
  conversationId?: unknown;
  timezone?: unknown;
}

interface ChatWithAIResponse {
  reply: string;
  draftEvents?: DraftEvent[];
}

interface DebugOpenAIHealthCheckResponse {
  ok: boolean;
  secretAvailable: boolean;
  secretSource: string;
  secretLength: number;
  model: string;
  reply: string;
}

interface SummarizeVoiceMemoRequest {
  input?: unknown;
  inputMode?: unknown;
  timezone?: unknown;
  currentDateISO?: unknown;
}

interface VoiceMemoSummaryResponse {
  title: string;
  summary: string;
  detailedSummary: string;
  keyPoints: string[];
  actionItems: string[];
  category: string;
}

interface RealtimeTranscriptionClientSecretResponse {
  clientSecret: string;
  expiresAt: number;
  model: string;
  sampleRate: number;
}

interface AnalyzeMemoTaskRequest {
  title?: unknown;
  body?: unknown;
  timezone?: unknown;
  currentDateISO?: unknown;
}

interface SummarizeRecordedVoiceMemoRequest {
  memoId?: unknown;
}

interface RecordedVoiceMemoSummaryResponse {
  status: string;
  summary: string;
  transcriptChunkCount: number;
}

interface MemoTaskDraftResponse {
  title: string;
  notes: string;
  category?: string;
  dateISO?: string;
  time24h?: string;
  reminderEnabled: boolean;
  confidence?: number;
}

const rateLimitWindowMs = 10 * 1000;
const rateLimitMaxCalls = 3;
const userCallTimestamps = new Map<string, number[]>();

//const pruneAndCheckRateLimit = (uid: string): void => {
const pruneAndCheckRateLimit = (key: string): void => {
  const now = Date.now();
  //const timestamps = userCallTimestamps.get(uid) || [];
  const timestamps = userCallTimestamps.get(key) || [];
  const fresh = timestamps.filter((ts) => now - ts < rateLimitWindowMs);

  if (fresh.length >= rateLimitMaxCalls) {
    throw new HttpsError(
      "resource-exhausted",
      "Too many requests. Please wait a few seconds and try again."
    );
  }

  fresh.push(now);
//   userCallTimestamps.set(uid, fresh);
  userCallTimestamps.set(key, fresh);
};

const functionErrorDetails = (error: unknown): Record<string, unknown> => {
  if (error instanceof Error) {
    const record = error as Error & Record<string, unknown>;
    return {
      name: error.name,
      message: error.message,
      code: record.code,
      status: record.status,
      type: record.type,
      details: record.details,
      stack: error.stack,
    };
  }

  if (error && typeof error === "object") {
    const record = error as Record<string, unknown>;
    return {
      name: record.name,
      message: record.message,
      code: record.code,
      status: record.status,
      type: record.type,
    };
  }

  return {
    message: String(error),
  };
};

const previewText = (value: string, maxLength = 1200): string => {
  return value.length > maxLength ? `${value.slice(0, maxLength)}...` : value;
};

const parseAssistantJson = (content: string): ChatWithAIResponse => {
  let parsed: unknown;
  try {
    parsed = JSON.parse(content);
  } catch (error) {
    logger.error("Assistant response is not valid JSON", error);
    throw new HttpsError("internal", "AI response format error.");
  }

  if (!parsed || typeof parsed !== "object") {
    throw new HttpsError("internal", "AI response format invalid.");
  }

  const candidate = parsed as Record<string, unknown>;
  const reply = typeof candidate.reply === "string" ? candidate.reply.trim() : "";
  if (!reply) {
    throw new HttpsError("internal", "AI response missing reply.");
  }

  const response: ChatWithAIResponse = {reply};

  if (Array.isArray(candidate.draftEvents)) {
    const draftEvents: DraftEvent[] = candidate.draftEvents
      .filter((item) => item && typeof item === "object")
      .map((item) => {
        const event = item as Record<string, unknown>;
        return {
          title: typeof event.title === "string" ? event.title : "Untitled",
          startISO: typeof event.startISO === "string" ? event.startISO : undefined,
          endISO: typeof event.endISO === "string" ? event.endISO : undefined,
          dateISO: typeof event.dateISO === "string" ? event.dateISO : undefined,
          timeISO: typeof event.timeISO === "string" ? event.timeISO : undefined,
          timezone: typeof event.timezone === "string" ? event.timezone : undefined,
          participants: Array.isArray(event.participants) ?
            event.participants.filter((p): p is string => typeof p === "string") : undefined,
          location: typeof event.location === "string" ? event.location : undefined,
          notes: typeof event.notes === "string" ? event.notes : undefined,
          confidence: typeof event.confidence === "number" ? event.confidence : undefined,
        };
      });

    if (draftEvents.length > 0) {
      response.draftEvents = draftEvents;
    }
  }

  return response;
};

const parseVoiceMemoJson = (content: string): VoiceMemoSummaryResponse => {
  let parsed: unknown;
  try {
    const trimmed = content.trim();
    const jsonContent =
      trimmed.startsWith("```") ?
        trimmed.replace(/^```(?:json)?\s*/i, "").replace(/\s*```$/, "") :
        trimmed;
    parsed = JSON.parse(jsonContent);
  } catch (error) {
    logger.error("Voice memo response is not valid JSON", error);
    throw new HttpsError("internal", "AI response format error.");
  }

  if (!parsed || typeof parsed !== "object") {
    throw new HttpsError("internal", "AI response format invalid.");
  }

  const candidate = parsed as Record<string, unknown>;
  const title = typeof candidate.title === "string" ? candidate.title.trim() : "";
  const summary = typeof candidate.summary === "string" ? candidate.summary.trim() : "";
  const detailedSummary =
    typeof candidate.detailedSummary === "string" ?
      candidate.detailedSummary.trim() :
      "";
  const category = typeof candidate.category === "string" ? candidate.category.trim() : "Memo";

  if (!title || !summary || !detailedSummary) {
    throw new HttpsError("internal", "AI memo response missing required fields.");
  }

  const keyPoints = Array.isArray(candidate.keyPoints) ?
    candidate.keyPoints
      .filter((item): item is string => typeof item === "string")
      .map((item) => item.trim())
      .filter((item) => item.length > 0) :
    [];

  const actionItems = Array.isArray(candidate.actionItems) ?
    candidate.actionItems
      .filter((item): item is string => typeof item === "string")
      .map((item) => item.trim())
      .filter((item) => item.length > 0) :
    [];

  return {
    title,
    summary: limitText(summary),
    detailedSummary: limitText(detailedSummary),
    keyPoints: limitTextItems(keyPoints),
    actionItems: limitTextItems(actionItems),
    category: category || "Memo",
  };
};

const isValidDateISO = (value: string): boolean => {
  if (!/^\d{4}-\d{2}-\d{2}$/.test(value)) {
    return false;
  }

  const date = new Date(`${value}T00:00:00Z`);
  return !Number.isNaN(date.getTime()) && date.toISOString().slice(0, 10) === value;
};

const formatDateInTimezone = (date: Date, timezone: string): string => {
  const build = (timeZone: string): string => {
    const parts = new Intl.DateTimeFormat("en-CA", {
      timeZone,
      year: "numeric",
      month: "2-digit",
      day: "2-digit",
    }).formatToParts(date);

    const year = parts.find((part) => part.type === "year")?.value;
    const month = parts.find((part) => part.type === "month")?.value;
    const day = parts.find((part) => part.type === "day")?.value;

    if (!year || !month || !day) {
      throw new Error("Unable to format current date.");
    }

    return `${year}-${month}-${day}`;
  };

  try {
    return build(timezone);
  } catch (_) {
    return build(DEFAULT_TIMEZONE);
  }
};

const resolveCurrentDateISO = (value: unknown, timezone: string): string => {
  if (typeof value === "string") {
    const trimmed = value.trim();
    if (isValidDateISO(trimmed)) {
      return trimmed;
    }
  }

  return formatDateInTimezone(new Date(), timezone);
};

const addDaysToDateISO = (dateISO: string, days: number): string => {
  const date = new Date(`${dateISO}T00:00:00Z`);
  date.setUTCDate(date.getUTCDate() + days);
  return date.toISOString().slice(0, 10);
};

const inferRelativeDateISO = (input: string, currentDateISO: string): string | undefined => {
  const normalized = input.toLowerCase();

  if (/(后天|day after tomorrow)/i.test(normalized)) {
    return addDaysToDateISO(currentDateISO, 2);
  }

  if (/(明天|tomorrow)/i.test(normalized)) {
    return addDaysToDateISO(currentDateISO, 1);
  }

  if (/(今天|今日|today)/i.test(normalized)) {
    return currentDateISO;
  }

  return undefined;
};

const normalizeMemoTaskDateISO = (
  value: string | undefined,
  sourceText: string,
  currentDateISO: string
): string | undefined => {
  const inferredDateISO = inferRelativeDateISO(sourceText, currentDateISO);
  if (inferredDateISO) {
    return inferredDateISO;
  }

  const trimmed = value?.trim();
  if (!trimmed || !isValidDateISO(trimmed)) {
    return undefined;
  }

  const currentYear = Number(currentDateISO.slice(0, 4));
  const draftYear = Number(trimmed.slice(0, 4));
  const hasExplicitYear = /\b(?:19|20)\d{2}\b/.test(sourceText);
  if (!hasExplicitYear && draftYear < currentYear) {
    return undefined;
  }

  return trimmed;
};

const limitText = (value: string, maxChars = MAX_SUMMARY_CHARS): string => {
  const normalized = value.replace(/\s+/g, " ").trim();
  const chars = Array.from(normalized);
  if (chars.length <= maxChars) {
    return normalized;
  }

  return chars.slice(0, maxChars).join("").trimEnd();
};

const limitTextItems = (items: string[]): string[] =>
  items
    .map((item) => limitText(item))
    .filter((item) => item.length > 0);

const parseMemoTaskJson = (content: string): MemoTaskDraftResponse => {
  let parsed: unknown;
  let jsonContent = content;
  try {
    const trimmed = content.trim();
    jsonContent =
      trimmed.startsWith("```") ?
        trimmed.replace(/^```(?:json)?\s*/i, "").replace(/\s*```$/, "") :
        trimmed;
    parsed = JSON.parse(jsonContent);
  } catch (error) {
    logger.error("Memo task response is not valid JSON", {
      error,
      rawResponsePreview: previewText(jsonContent),
    });
    throw new HttpsError(
      "unknown",
      "AI response was not valid JSON.",
      {
        rawResponsePreview: previewText(jsonContent),
        errorMessage: error instanceof Error ? error.message : String(error),
      }
    );
  }

  if (!parsed || typeof parsed !== "object") {
    throw new HttpsError("unknown", "AI response format invalid.");
  }

  const candidate = parsed as Record<string, unknown>;
  const title = typeof candidate.title === "string" ? candidate.title.trim() : "";
  const notes = typeof candidate.notes === "string" ? candidate.notes.trim() : "";

  if (!title && !notes) {
    throw new HttpsError(
      "invalid-argument",
      "No clear event details found in this memo.",
      {
        rawResponsePreview: previewText(jsonContent),
      }
    );
  }

  return {
    title,
    notes,
    category: typeof candidate.category === "string" ? candidate.category.trim() : undefined,
    dateISO: typeof candidate.dateISO === "string" ? candidate.dateISO.trim() : undefined,
    time24h: typeof candidate.time24h === "string" ? candidate.time24h.trim() : undefined,
    reminderEnabled: typeof candidate.reminderEnabled === "boolean" ? candidate.reminderEnabled : true,
    confidence: typeof candidate.confidence === "number" ? candidate.confidence : undefined,
  };
};

const detectVoiceMemoCategory = (input: string): string => {
  const normalized = input.toLowerCase();

  if (/(meeting|project|deadline|client|demo|team|work)/.test(normalized)) {
    return "Work";
  }

  if (/(family|mom|dad|child|kids|home|share)/.test(normalized)) {
    return "Family";
  }

  if (/(doctor|health|exercise|medicine|sleep)/.test(normalized)) {
    return "Health";
  }

  if (/(study|school|class|assignment|exam|course)/.test(normalized)) {
    return "Study";
  }

  if (/(buy|shopping|groceries|pick up|errand|store)/.test(normalized)) {
    return "Errand";
  }

  return "Memo";
};

const buildVoiceMemoFallback = (input: string): VoiceMemoSummaryResponse => {
  const cleaned = input.replace(/\s+/g, " ").trim();
  const segments = cleaned
    .split(/(?<=[.!?])\s+/)
    .map((segment) => segment.trim())
    .filter((segment) => segment.length > 0);

  const titleSource = segments[0] || cleaned;
  const titleWords = titleSource.split(" ").filter((word) => word.length > 0).slice(0, 8);
  const title = titleWords.join(" ") || "Voice memo";
  const summary =
    segments.slice(0, 2).join(" ").trim() ||
    cleaned.substring(0, 160).trim();
  const detailedSummary =
    segments.slice(0, 4).join(" ").trim() ||
    cleaned;

  const keyPoints = segments.slice(0, 3);
  const actionItems = segments
    .filter((segment) => /(need to|should|plan to|must|follow up|next)/i.test(segment))
    .slice(0, 3);

  return {
    title,
    summary: limitText(summary || "Summary generated from the memo content."),
    detailedSummary:
      limitText(detailedSummary || "Detailed summary generated from the memo content."),
    keyPoints: limitTextItems(keyPoints),
    actionItems: limitTextItems(actionItems),
    category: detectVoiceMemoCategory(cleaned),
  };
};

const parseRecordedMemoSummaryJson = (content: string): string => {
  let parsed: unknown;
  try {
    const trimmed = content.trim();
    const jsonContent =
      trimmed.startsWith("```") ?
        trimmed.replace(/^```(?:json)?\s*/i, "").replace(/\s*```$/, "") :
        trimmed;
    parsed = JSON.parse(jsonContent);
  } catch (error) {
    logger.error("Recorded voice memo summary response is not valid JSON", error);
    throw new HttpsError("internal", "AI response format error.");
  }

  if (!parsed || typeof parsed !== "object") {
    throw new HttpsError("internal", "AI response format invalid.");
  }

  const summary = (parsed as Record<string, unknown>).summary;
  if (typeof summary !== "string") {
    throw new HttpsError("internal", "AI response missing summary.");
  }

  return summary.replace(/\s+\n/g, "\n").replace(/\n{3,}/g, "\n\n").trim();
};

const runFfmpeg = async (args: string[]): Promise<void> => {
  await execFileAsync(ffmpegInstaller.path, args, {maxBuffer: 1024 * 1024 * 8});
};

const listSegmentFiles = (dir: string): string[] => {
  return fs.readdirSync(dir)
    .filter((name) => /^chunk_\d+\.m4a$/.test(name))
    .sort()
    .map((name) => path.join(dir, name))
    .filter((filePath) => fs.statSync(filePath).size > 0);
};

const splitAudioForTranscription = async (
  inputPath: string,
  workDir: string
): Promise<string[]> => {
  if (fs.statSync(inputPath).size <= MAX_TRANSCRIPTION_FILE_BYTES) {
    return [inputPath];
  }

  let segmentSeconds = AUDIO_SEGMENT_SECONDS;
  for (let attempt = 0; attempt < 4; attempt++) {
    const segmentDir = path.join(workDir, `segments_${attempt}`);
    fs.rmSync(segmentDir, {recursive: true, force: true});
    fs.mkdirSync(segmentDir, {recursive: true});
    const outputPattern = path.join(segmentDir, "chunk_%03d.m4a");

    const baseArgs = [
      "-y",
      "-i",
      inputPath,
      "-vn",
      "-f",
      "segment",
      "-segment_time",
      String(segmentSeconds),
      "-reset_timestamps",
      "1",
    ];

    try {
      await runFfmpeg([...baseArgs, "-c", "copy", outputPattern]);
    } catch (_) {
      await runFfmpeg([
        ...baseArgs,
        "-c:a",
        "aac",
        "-b:a",
        "64k",
        "-ac",
        "1",
        "-ar",
        "44100",
        outputPattern,
      ]);
    }

    const chunks = listSegmentFiles(segmentDir);
    if (
      chunks.length > 0 &&
      chunks.every((chunk) => fs.statSync(chunk).size <= MAX_TRANSCRIPTION_FILE_BYTES)
    ) {
      return chunks;
    }

    segmentSeconds = Math.max(120, Math.floor(segmentSeconds / 2));
  }

  throw new HttpsError("resource-exhausted", "Recording is too large to process.");
};

const transcribeAudioChunks = async (
  openai: OpenAI,
  chunkPaths: string[]
): Promise<string[]> => {
  const transcripts: string[] = [];

  for (const [index, chunkPath] of chunkPaths.entries()) {
    const transcription = await openai.audio.transcriptions.create({
      file: fs.createReadStream(chunkPath),
      model: RECORDING_TRANSCRIBE_MODEL,
      response_format: "json",
      prompt: [
        "This is a personal voice memo for a family calendar app.",
        "Transcribe accurately in the spoken language.",
        "Preserve names, dates, times, task wording, and reminders.",
        `This is segment ${index + 1} of ${chunkPaths.length}.`,
      ].join(" "),
    });

    const text = typeof transcription === "string" ?
      transcription :
      transcription.text;
    const cleaned = (text || "").replace(/\s+/g, " ").trim();
    if (cleaned) {
      transcripts.push(cleaned);
    }
  }

  return transcripts;
};

const summarizeRecordedTranscript = async (
  openai: OpenAI,
  transcript: string
): Promise<string> => {
  const systemPrompt = [
    "You summarize recorded voice memos for a family calendar app.",
    "The transcript may contain multiple chronological chunks from one recording.",
    "Create note text that is useful inside the memo's Notes field.",
    "Do not reveal or quote the raw transcript.",
    "Do not mention transcription, chunks, audio quality, or AI.",
    "Preserve concrete names, dates, times, places, tasks, and decisions.",
    "Do not invent details that are not present.",
    "The transcript may be long, fragmented, disfluent, or separated by pauses.",
    "If any recognizable content is present, summarize the useful partial information.",
    "If the transcript is only repeated test text, random characters, filler, or noise, answer quickly with no recognized information.",
    `Return ${JSON.stringify(NO_RECOGNIZED_INFO)} only when the transcript contains no recognizable words or only meaningless filler.`,
  ].join(" ");

  const developerPrompt = [
    "Return JSON only.",
    "Schema: { \"summary\": \"string\" }",
    "Write the summary in English, regardless of the transcript language.",
    "Use a concise paragraph or short bullet-style lines.",
    "Keep the summary under 900 characters.",
    "Include clear action items or reminders when they are present.",
    "Never copy or repeat long raw transcript text.",
    `Do not return ${NO_RECOGNIZED_INFO} solely because the memo is long, broken up, or lacks a perfect sentence structure.`,
  ].join("\n");

  const completion = await openai.chat.completions.create({
    model: RECORDING_SUMMARY_MODEL,
    temperature: 0.2,
    max_tokens: 260,
    response_format: {type: "json_object"},
    messages: [
      {role: "system", content: systemPrompt},
      {role: "developer", content: developerPrompt},
      {role: "user", content: `Transcript:\n${transcript}`},
    ],
  });

  const content = completion.choices[0]?.message?.content;
  if (!content) {
    throw new HttpsError("internal", "No response from AI model.");
  }

  return parseRecordedMemoSummaryJson(content) || NO_RECOGNIZED_INFO;
};

const processRecordedVoiceMemo = async (
  memoId: string,
  expectedUserId?: string
): Promise<RecordedVoiceMemoSummaryResponse> => {
  const apiKey = openAiKeySecret.value() || process.env.OPENAI_API_KEY;
  if (!apiKey) {
    logger.error("OPENAI_API_KEY is missing");
    throw new HttpsError("internal", "Server is not configured for AI service.");
  }

  const firestore = getFirestore();
  const memoRef = firestore.collection("memos").doc(memoId);
  const memoSnapshot = await memoRef.get();
  if (!memoSnapshot.exists) {
    throw new HttpsError("not-found", "Voice memo was not found.");
  }

  const memo = memoSnapshot.data() ?? {};
  const memoUserId = typeof memo.userId === "string" ? memo.userId : "";
  if (expectedUserId && memoUserId !== expectedUserId) {
    throw new HttpsError("permission-denied", "You cannot summarize this memo.");
  }

  const existingStatus =
    typeof memo.aiSummaryStatus === "string" ? memo.aiSummaryStatus : "";
  const existingBody = typeof memo.body === "string" ? memo.body.trim() : "";
  if (existingStatus && existingStatus !== "pending") {
    return {
      status: existingStatus,
      summary: existingBody,
      transcriptChunkCount:
        typeof memo.transcriptChunkCount === "number" ? memo.transcriptChunkCount : 0,
    };
  }

  const audioStoragePath =
    typeof memo.audioStoragePath === "string" ? memo.audioStoragePath.trim() : "";
  if (!audioStoragePath) {
    await memoRef.update({
      aiSummaryStatus: "failed",
      aiSummaryError: "Missing uploaded audio.",
      updatedAt: FieldValue.serverTimestamp(),
    });
    throw new HttpsError("failed-precondition", "Uploaded audio is not available.");
  }

  await memoRef.update({
    aiSummaryStatus: "processing",
    aiSummaryError: FieldValue.delete(),
    updatedAt: FieldValue.serverTimestamp(),
  });

  const tempDir = fs.mkdtempSync(path.join(os.tmpdir(), `voice-memo-${memoId}-`));
  const inputPath = path.join(tempDir, "recording.m4a");
  const openai = new OpenAI({apiKey});

  try {
    await getStorage().bucket().file(audioStoragePath).download({
      destination: inputPath,
    });

    const downloadedAudioBytes = fs.statSync(inputPath).size;
    const chunkPaths = await splitAudioForTranscription(inputPath, tempDir);
    const transcripts = await transcribeAudioChunks(openai, chunkPaths);
    const fullTranscript = transcripts.join("\n\n").trim();
    logger.info("Recorded voice memo transcription finished", {
      memoId,
      downloadedAudioBytes,
      chunkCount: chunkPaths.length,
      transcriptTextLength: fullTranscript.length,
    });

    if (!fullTranscript) {
      await memoRef.update({
        body: NO_RECOGNIZED_INFO,
        aiSummaryStatus: "no_speech",
        aiSummaryModel: RECORDING_SUMMARY_MODEL,
        aiTranscriptionModel: RECORDING_TRANSCRIBE_MODEL,
        audioFileBytes: downloadedAudioBytes,
        transcriptTextLength: 0,
        transcriptChunkCount: chunkPaths.length,
        updatedAt: FieldValue.serverTimestamp(),
      });

      return {
        status: "no_speech",
        summary: NO_RECOGNIZED_INFO,
        transcriptChunkCount: chunkPaths.length,
      };
    }

    const summary = await summarizeRecordedTranscript(openai, fullTranscript);
    await memoRef.update({
      body: summary,
      aiSummaryStatus: summary === NO_RECOGNIZED_INFO ? "no_speech" : "completed",
      aiSummaryModel: RECORDING_SUMMARY_MODEL,
      aiTranscriptionModel: RECORDING_TRANSCRIBE_MODEL,
      audioFileBytes: downloadedAudioBytes,
      transcriptTextLength: fullTranscript.length,
      transcriptChunkCount: chunkPaths.length,
      updatedAt: FieldValue.serverTimestamp(),
    });

    return {
      status: summary === NO_RECOGNIZED_INFO ? "no_speech" : "completed",
      summary,
      transcriptChunkCount: chunkPaths.length,
    };
  } catch (error) {
    logger.error("processRecordedVoiceMemo failed", error);
    await memoRef.update({
      aiSummaryStatus: "failed",
      aiSummaryError: error instanceof Error ? error.message : "Processing failed.",
      updatedAt: FieldValue.serverTimestamp(),
    });

    if (error instanceof HttpsError) {
      throw error;
    }
    throw new HttpsError("internal", "Failed to summarize recording.");
  } finally {
    fs.rmSync(tempDir, {recursive: true, force: true});
  }
};

export const chatWithAI = onCall(
  {secrets: [openAiKeySecret], region: "australia-southeast1" },
  async (request): Promise<ChatWithAIResponse> => {
//     if (!request.auth?.uid) {
//       throw new HttpsError("unauthenticated", "You must be logged in to use AI chat.");
//     }
//
//     pruneAndCheckRateLimit(request.auth.uid);
    const callerKey =
          request.auth?.uid ||
          (request.rawRequest as any)?.ip ||
          "anon";

    pruneAndCheckRateLimit(callerKey);

    const data = (request.data ?? {}) as ChatWithAIRequest;
    const message = typeof data.message === "string" ? data.message.trim() : "";
    const conversationId =
      typeof data.conversationId === "string" ? data.conversationId.trim() : "";
    const timezone =
      typeof data.timezone === "string" && data.timezone.trim().length > 0 ?
        data.timezone.trim() :
        DEFAULT_TIMEZONE;

    if (!message) {
      throw new HttpsError("invalid-argument", "message is required.");
    }

    const apiKey = openAiKeySecret.value() || process.env.OPENAI_API_KEY;
    if (!apiKey) {
      logger.error("OPENAI_API_KEY is missing");
      throw new HttpsError(
        "failed-precondition",
        "Server is not configured for AI service.",
        {reason: "OPENAI_API_KEY is missing"}
      );
    }

    const openai = new OpenAI({apiKey});

    const systemPrompt = [
      "You are the Family Calendar AI Assistant.",
      "Help users organize schedules, reminders, and todos from conversation.",
      "Return strict JSON with two top-level fields: reply (string) and draftEvents (array).",
      "In reply: be friendly, concise, and confirm key details.",
      "In draftEvents: include possible schedule/reminder drafts when detected.",
      "Prefer startISO/endISO, or dateISO/timeISO when full datetime is unavailable.",
      "Never fabricate dates or times. If any critical detail is missing, ask a clarifying question.",
      "Do not output sensitive data.",
      "Do not claim that events are already created.",
      `Default timezone is ${timezone}.`,
      "If no event-like intent exists, return an empty draftEvents array.",
    ].join(" ");

    const developerPrompt = [
      "Return JSON only.",
      "Schema:",
      "{",
      "  \"reply\": \"string\",",
      "  \"draftEvents\": [",
      "    {",
      "      \"title\": \"string\",",
      "      \"startISO\": \"string (optional)\",",
      "      \"endISO\": \"string (optional)\",",
      "      \"dateISO\": \"string (optional)\",",
      "      \"timeISO\": \"string (optional)\",",
      "      \"timezone\": \"string (optional)\",",
      "      \"participants\": [\"string\"] (optional),",
      "      \"location\": \"string (optional)\",",
      "      \"notes\": \"string (optional)\",",
      "      \"confidence\": \"number 0..1 (optional)\"",
      "    }",
      "  ]",
      "}",
      "Use English in reply.",
      "Use conversationId only as metadata context if provided; do not expose secrets.",
    ].join("\n");

    const userPrompt = `conversationId: ${conversationId || "n/a"}\nuserMessage: ${message}`;

    try {
      const completion = await openai.chat.completions.create({
        model: DEFAULT_MODEL,
        temperature: 0.2,
        response_format: {type: "json_object"},
        messages: [
          {role: "system", content: systemPrompt},
          {role: "developer", content: developerPrompt},
          {role: "user", content: userPrompt},
        ],
      });

      const content = completion.choices[0]?.message?.content;
      if (!content) {
        throw new HttpsError("unknown", "No response from AI model.");
      }

      return parseAssistantJson(content);
    } catch (error) {
      if (error instanceof HttpsError) {
        throw error;
      }
      logger.error("chatWithAI failed", error);
      throw new HttpsError("internal", "Failed to process AI request.");
    }
  }
);

export const debugOpenAIHealthCheck = onCall(
  {
    secrets: [openAiKeySecret],
    region: "australia-southeast1",
    timeoutSeconds: 45,
  },
  async (request): Promise<DebugOpenAIHealthCheckResponse> => {
    const secretValue = openAiKeySecret.value();
    const envValue = process.env.OPENAI_API_KEY;
    const apiKey = secretValue || envValue;
    const secretSource = secretValue ? "firebase-secret" : envValue ? "env" : "missing";

    logger.info("debugOpenAIHealthCheck started", {
      uid: request.auth?.uid ?? "anonymous",
      secretAvailable: Boolean(apiKey),
      secretSource,
      secretLength: apiKey?.length ?? 0,
      model: DEFAULT_MODEL,
    });

    if (!apiKey) {
      throw new HttpsError(
        "failed-precondition",
        "OPENAI_API_KEY is not available in the cloud function runtime.",
        {
          secretAvailable: false,
          secretSource,
        }
      );
    }

    try {
      const openai = new OpenAI({
        apiKey,
        timeout: 30000,
      });

      const completion = await openai.chat.completions.create({
        model: DEFAULT_MODEL,
        temperature: 0,
        max_tokens: 40,
        response_format: {type: "json_object"},
        messages: [
          {
            role: "system",
            content: "Return JSON only.",
          },
          {
            role: "user",
            content: "Return {\"ok\":true,\"source\":\"firebase-function\"}.",
          },
        ],
      });

      const reply = completion.choices[0]?.message?.content ?? "";
      if (!reply) {
        throw new HttpsError("unknown", "OpenAI returned no content.");
      }

      logger.info("debugOpenAIHealthCheck finished", {
        uid: request.auth?.uid ?? "anonymous",
        replyLength: reply.length,
      });

      return {
        ok: true,
        secretAvailable: true,
        secretSource,
        secretLength: apiKey.length,
        model: DEFAULT_MODEL,
        reply,
      };
    } catch (error) {
      if (error instanceof HttpsError) {
        throw error;
      }

      logger.error("debugOpenAIHealthCheck failed", error);
      throw new HttpsError(
        "unknown",
        "OpenAI health check failed.",
        functionErrorDetails(error)
      );
    }
  }
);

export const createRealtimeTranscriptionClientSecret = onCall(
  {secrets: [openAiKeySecret], region: "australia-southeast1"},
  async (request): Promise<RealtimeTranscriptionClientSecretResponse> => {
    if (!request.auth?.uid) {
      throw new HttpsError("unauthenticated", "You must be logged in to use voice input.");
    }

    pruneAndCheckRateLimit(`${request.auth.uid}:realtime-transcription`);

    const apiKey = openAiKeySecret.value() || process.env.OPENAI_API_KEY;
    if (!apiKey) {
      logger.error("OPENAI_API_KEY is missing");
      throw new HttpsError("internal", "Server is not configured for AI service.");
    }

    const response = await fetch("https://api.openai.com/v1/realtime/client_secrets", {
      method: "POST",
      headers: {
        "Authorization": `Bearer ${apiKey}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify({
        expires_after: {
          anchor: "created_at",
          seconds: 120,
        },
        session: {
          type: "transcription",
          audio: {
            input: {
              format: {
                type: "audio/pcm",
                rate: REALTIME_TRANSCRIBE_SAMPLE_RATE,
              },
              transcription: {
                model: REALTIME_TRANSCRIBE_MODEL,
              },
            },
          },
        },
      }),
    });

    const rawBody = await response.text();
    if (!response.ok) {
      logger.error("Realtime client secret request failed", {
        status: response.status,
        body: rawBody,
      });
      throw new HttpsError("internal", "Failed to start realtime voice input.");
    }

    const parsed = JSON.parse(rawBody) as Record<string, unknown>;
    const nestedClientSecret = parsed.client_secret as Record<string, unknown> | undefined;
    const session = parsed.session as Record<string, unknown> | undefined;
    const sessionClientSecret = session?.client_secret as Record<string, unknown> | undefined;
    const clientSecret =
      typeof parsed.value === "string" ?
        parsed.value :
        typeof nestedClientSecret?.value === "string" ?
          nestedClientSecret.value :
          typeof sessionClientSecret?.value === "string" ?
            sessionClientSecret.value :
            "";
    const expiresAt =
      typeof parsed.expires_at === "number" ?
        parsed.expires_at :
        typeof nestedClientSecret?.expires_at === "number" ?
          nestedClientSecret.expires_at :
          typeof sessionClientSecret?.expires_at === "number" ?
            sessionClientSecret.expires_at :
            0;

    if (!clientSecret) {
      logger.error("Realtime client secret response did not include a token", parsed);
      throw new HttpsError("internal", "Failed to start realtime voice input.");
    }

    return {
      clientSecret,
      expiresAt,
      model: REALTIME_TRANSCRIBE_MODEL,
      sampleRate: REALTIME_TRANSCRIBE_SAMPLE_RATE,
    };
  }
);

export const summarizeVoiceMemo = onCall(
  {secrets: [openAiKeySecret], region: "australia-southeast1"},
  async (request): Promise<VoiceMemoSummaryResponse> => {
    if (!request.auth?.uid) {
      throw new HttpsError("unauthenticated", "You must be logged in to summarize a memo.");
    }

    pruneAndCheckRateLimit(request.auth.uid);

    const data = (request.data ?? {}) as SummarizeVoiceMemoRequest;
    const input = typeof data.input === "string" ? data.input.trim() : "";
    const inputMode = typeof data.inputMode === "string" ? data.inputMode.trim() : "text";
    const timezone =
      typeof data.timezone === "string" && data.timezone.trim().length > 0 ?
        data.timezone.trim() :
        DEFAULT_TIMEZONE;
    const currentDateISO = resolveCurrentDateISO(data.currentDateISO, timezone);

    if (!input) {
      throw new HttpsError("invalid-argument", "input is required.");
    }

    const apiKey = openAiKeySecret.value() || process.env.OPENAI_API_KEY;
    if (!apiKey) {
      logger.error("OPENAI_API_KEY is missing");
      throw new HttpsError("internal", "Server is not configured for AI service.");
    }

    const openai = new OpenAI({apiKey, timeout: 30000});

    const systemPrompt = [
      "You are the Family Calendar voice memo assistant.",
      "Turn raw personal notes into a clean structured summary.",
      "Preserve user intent, avoid fabrication, and be concise but helpful.",
      "Infer a short memo category such as Family, Work, Health, Study, Errand, or Personal.",
      "If action items are implied, list them briefly. If none exist, return an empty array.",
      "If the input is only repeated test text, random characters, filler, or noise, answer quickly with no recognized information.",
      `Assume timezone ${timezone} for interpretation context only.`,
      `The current local date is ${currentDateISO}.`,
    ].join(" ");

    const developerPrompt = [
      "Return JSON only.",
      "Schema:",
      "{",
      "  \"title\": \"string up to 8 words\",",
      `  "summary": "string, 1-2 sentences, max ${MAX_SUMMARY_CHARS} characters",`,
      `  "detailedSummary": "string, concise paragraph, max ${MAX_SUMMARY_CHARS} characters",`,
      "  \"keyPoints\": [\"string\"],",
      "  \"actionItems\": [\"string\"],",
      "  \"category\": \"string\"",
      "}",
      "Keep the output in English.",
      "Do not mention the schema.",
      `Keep summary, detailedSummary, and each list item within ${MAX_SUMMARY_CHARS} characters.`,
      "Never copy or repeat long raw input text.",
      "Do not invent dates, people, or commitments not present in the input.",
      "For meaningless input, return exactly:",
      `{ "title": "Untitled memo", "summary": ${JSON.stringify(NO_RECOGNIZED_INFO)}, "detailedSummary": ${JSON.stringify(NO_RECOGNIZED_INFO)}, "keyPoints": [], "actionItems": [], "category": "Personal" }`,
    ].join("\n");

    const userPrompt = `inputMode: ${inputMode}\nrawInput: ${input}`;

    try {
      const completion = await openai.chat.completions.create({
        model: DEFAULT_MODEL,
        temperature: 0.2,
        max_tokens: 300,
        response_format: {type: "json_object"},
        messages: [
          {role: "system", content: systemPrompt},
          {role: "developer", content: developerPrompt},
          {role: "user", content: userPrompt},
        ],
      });

      const content = completion.choices[0]?.message?.content;
      if (!content) {
        throw new HttpsError("internal", "No response from AI model.");
      }

      return parseVoiceMemoJson(content);
    } catch (error) {
      if (error instanceof HttpsError && error.code === "invalid-argument") {
        throw error;
      }

      logger.error("summarizeVoiceMemo failed", error);
      return buildVoiceMemoFallback(input);
    }
  }
);

export const summarizeRecordedVoiceMemo = onCall(
  {
    secrets: [openAiKeySecret],
    region: "australia-southeast1",
    timeoutSeconds: 540,
    memory: "1GiB",
  },
  async (request): Promise<RecordedVoiceMemoSummaryResponse> => {
    if (!request.auth?.uid) {
      throw new HttpsError("unauthenticated", "You must be logged in to summarize a recording.");
    }

    pruneAndCheckRateLimit(request.auth.uid);

    const data = (request.data ?? {}) as SummarizeRecordedVoiceMemoRequest;
    const memoId = typeof data.memoId === "string" ? data.memoId.trim() : "";
    if (!memoId) {
      throw new HttpsError("invalid-argument", "memoId is required.");
    }

    return processRecordedVoiceMemo(memoId, request.auth.uid);
  }
);

export const summarizeRecordedVoiceMemoOnCreate = onDocumentCreated(
  {
    document: "memos/{memoId}",
    secrets: [openAiKeySecret],
    region: "australia-southeast1",
    timeoutSeconds: 540,
    memory: "1GiB",
  },
  async (event): Promise<void> => {
    const memo = event.data?.data();
    if (!memo) {
      return;
    }

    if (
      memo.memoType !== "voice" ||
      memo.aiSummaryStatus !== "pending" ||
      typeof memo.audioStoragePath !== "string" ||
      memo.audioStoragePath.trim().length === 0
    ) {
      return;
    }

    await processRecordedVoiceMemo(event.params.memoId);
  }
);

export const analyzeMemoToTask = onCall(
  {
    secrets: [openAiKeySecret],
    region: "australia-southeast1",
    timeoutSeconds: 60,
  },
  async (request): Promise<MemoTaskDraftResponse> => {
    const startedAt = Date.now();
    const checkpoint = (
      step: string,
      extra: Record<string, unknown> = {}
    ): void => {
      logger.info("analyzeMemoToTask checkpoint", {
        step,
        elapsedMs: Date.now() - startedAt,
        uid: request.auth?.uid ?? "anonymous",
        ...extra,
      });
    };

    checkpoint("start");

    if (!request.auth?.uid) {
      throw new HttpsError("unauthenticated", "You must be logged in to analyze a memo.");
    }

    pruneAndCheckRateLimit(request.auth.uid);
    checkpoint("auth-and-rate-limit-ok");

    const data = (request.data ?? {}) as AnalyzeMemoTaskRequest;
    const title = typeof data.title === "string" ? data.title.trim() : "";
    const body = typeof data.body === "string" ? data.body.trim() : "";
    const timezone =
      typeof data.timezone === "string" && data.timezone.trim().length > 0 ?
        data.timezone.trim() :
        DEFAULT_TIMEZONE;
    const currentDateISO = resolveCurrentDateISO(data.currentDateISO, timezone);

    if (!title && !body) {
      throw new HttpsError("invalid-argument", "Memo content is required.");
    }
    checkpoint("request-parsed", {
      titleLength: title.length,
      bodyLength: body.length,
      timezone,
      currentDateISO,
      titlePreview: previewText(title, 120),
      bodyPreview: previewText(body, 240),
    });

    const apiKey = openAiKeySecret.value() || process.env.OPENAI_API_KEY;
    if (!apiKey) {
      logger.error("OPENAI_API_KEY is missing");
      throw new HttpsError("internal", "Server is not configured for AI service.");
    }

    const openai = new OpenAI({apiKey});
    checkpoint("openai-client-created", {
      model: DEFAULT_MODEL,
    });

    const systemPrompt = [
      "You are the Family Calendar memo-to-task assistant.",
      "Read one memo and extract only clear event details that can prefill an add-task form.",
      "Never fabricate dates, times, titles, or reminders.",
      "If a field is unclear, leave it empty instead of guessing.",
      "If the memo is meaningless, repetitive, random text, or has no clear event/task intent, return empty strings.",
      "Do not copy or repeat long memo text into the output.",
      "Allowed category values are Education, Family, Leisure.",
      `Interpret date and time references in timezone ${timezone}.`,
      `The current local date is ${currentDateISO}.`,
    ].join(" ");

    const developerPrompt = [
      "Return JSON only.",
      "Schema:",
      "{",
      "  \"title\": \"string\",",
      "  \"notes\": \"string\",",
      "  \"category\": \"Education | Family | Leisure | empty string\",",
      "  \"dateISO\": \"YYYY-MM-DD or empty string\",",
      "  \"time24h\": \"HH:mm or empty string\",",
      "  \"reminderEnabled\": true,",
      "  \"confidence\": \"number 0..1\"",
      "}",
      "If no clear event/task details exist, return exactly:",
      "{ \"title\": \"\", \"notes\": \"\", \"category\": \"\", \"dateISO\": \"\", \"time24h\": \"\", \"reminderEnabled\": false, \"confidence\": 0 }",
      "Use memo wording where possible.",
      "If memo title is usable as task title, prefer it.",
      "Keep notes useful for the task detail field, max 180 characters.",
      "Never echo repetitive filler text.",
      `When the memo says today/今天/今日, use ${currentDateISO}.`,
      `When the memo says tomorrow/明天, use ${addDaysToDateISO(currentDateISO, 1)}.`,
      `When the memo says 后天/day after tomorrow, use ${addDaysToDateISO(currentDateISO, 2)}.`,
      "Do not invent a date or time from weak hints.",
    ].join("\n");

    const userPrompt = `memoTitle: ${title || "n/a"}\nmemoBody: ${body || "n/a"}`;

    try {
      checkpoint("openai-request-start", {
        userPromptLength: userPrompt.length,
      });
      const completion = await openai.chat.completions.create({
        model: DEFAULT_MODEL,
        temperature: 0.1,
        max_tokens: 300,
        response_format: {type: "json_object"},
        messages: [
          {role: "system", content: systemPrompt},
          {role: "developer", content: developerPrompt},
          {role: "user", content: userPrompt},
        ],
      });
      checkpoint("openai-request-finished");

      const content = completion.choices[0]?.message?.content;
      if (!content) {
        throw new HttpsError("internal", "No response from AI model.");
      }
      logger.info("analyzeMemoToTask raw model response", {
        elapsedMs: Date.now() - startedAt,
        contentLength: content.length,
        contentPreview: previewText(content),
      });

      const draft = parseMemoTaskJson(content);
      const sourceText = `${title}\n${body}`;
      checkpoint("ai-response-parsed", {
        draftTitle: draft.title,
        hasDate: Boolean(draft.dateISO),
        hasTime: Boolean(draft.time24h),
      });
      return {
        ...draft,
        dateISO: normalizeMemoTaskDateISO(draft.dateISO, sourceText, currentDateISO),
      };
    } catch (error) {
      if (error instanceof HttpsError) {
        logger.error("analyzeMemoToTask failed with HttpsError", {
          code: error.code,
          message: error.message,
          details: error.details,
        });
        throw new HttpsError(
          error.code === "internal" ? "unknown" : error.code,
          error.message,
          error.details ?? functionErrorDetails(error)
        );
      }
      logger.error("analyzeMemoToTask failed", error);
      throw new HttpsError(
        "unknown",
        "Failed to analyze memo.",
        functionErrorDetails(error)
      );
    }
  }
);
