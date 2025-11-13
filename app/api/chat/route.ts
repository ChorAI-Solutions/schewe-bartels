export async function POST(request: Request) {
  try {
    const body = await request.json().catch(() => ({}));
    const { message, sessionId, metadata } = body;

    if (!message || typeof message !== "string") {
      return Response.json(
        { error: "Message is required" },
        { status: 400 }
      );
    }

    if (!sessionId || typeof sessionId !== "string") {
      return Response.json(
        { error: "Session ID is required" },
        { status: 400 }
      );
    }

    const webhookUrl = process.env.N8N_CHATBOT_WEBHOOK_URL;
    if (!webhookUrl) {
      return Response.json(
        { error: "Webhook URL not configured on server" },
        { status: 500 }
      );
    }

    const payload = {
      chatInput: message,
      action: "sendMessage",
      sessionId,
      metadata: typeof metadata === "object" && metadata ? metadata : undefined,
    };

    const res = await fetch(webhookUrl, {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
      },
      body: JSON.stringify(payload),
    });

    if (!res.ok) {
      const errorText = await res.text().catch(() => "Unknown error");

      if (errorText.includes("<html")) {
        return Response.json(
          {
            error:
              "n8n workflow error - check n8n workflow configuration",
            details: "Received HTML error page",
          },
          { status: res.status }
        );
      }

      return Response.json(
        { error: "Failed to get response from chatbot", details: errorText },
        { status: res.status }
      );
    }

    const data = await res.json().catch(() => ({}));
    const reply =
      data.reply ||
      data.message ||
      data.text ||
      data.output ||
      "Entschuldigung, ich konnte keine Antwort generieren.";

    return Response.json({ reply }, { status: 200 });
  } catch (error) {
    console.error("Chat API error:", error);
    return Response.json(
      {
        error: "Internal server error",
        details: error instanceof Error ? error.message : String(error),
      },
      { status: 500 }
    );
  }
}
