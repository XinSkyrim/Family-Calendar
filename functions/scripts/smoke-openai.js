/* eslint-disable no-console, require-jsdoc, @typescript-eslint/no-var-requires */
const OpenAIModule = require("openai");

const OpenAI = OpenAIModule.default || OpenAIModule;

async function main() {
  const apiKey = process.env.OPENAI_API_KEY;
  const model = process.env.OPENAI_MODEL || "gpt-4o-mini";

  if (!apiKey) {
    console.error("OPENAI_API_KEY is not set.");
    console.error("PowerShell example:");
    console.error("$env:OPENAI_API_KEY = \"sk-...\"");
    process.exitCode = 1;
    return;
  }

  console.log(`Checking OpenAI model: ${model}`);

  const openai = new OpenAI({
    apiKey,
    timeout: 30000,
  });

  const completion = await openai.chat.completions.create({
    model,
    temperature: 0,
    max_tokens: 20,
    messages: [
      {
        role: "system",
        content: "Reply with JSON only.",
      },
      {
        role: "user",
        content: "Return {\"ok\":true,\"source\":\"smoke\"}.",
      },
    ],
    response_format: {type: "json_object"},
  });

  const content = completion.choices[0]?.message?.content;
  if (!content) {
    throw new Error("OpenAI returned no message content.");
  }

  console.log("OpenAI response:");
  console.log(content);
}

main().catch((error) => {
  console.error("OpenAI smoke test failed.");
  console.error(error);
  process.exitCode = 1;
});
