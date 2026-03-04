/* eslint-disable */
import OpenAI from "openai";
import {setGlobalOptions} from "firebase-functions/v2";
import {onCall, HttpsError} from "firebase-functions/v2/https";
import {defineSecret} from "firebase-functions/params";
import * as logger from "firebase-functions/logger";

setGlobalOptions({maxInstances: 10});

const openAiKeySecret = defineSecret("OPENAI_API_KEY");
const DEFAULT_MODEL = process.env.OPENAI_MODEL || "gpt-4o-mini";
const DEFAULT_TIMEZONE = "Australia/Adelaide";

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
      throw new HttpsError("internal", "Server is not configured for AI service.");
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
        throw new HttpsError("internal", "No response from AI model.");
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
