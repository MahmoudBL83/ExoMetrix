import { NextResponse } from "next/server";

const API_URL = process.env.INFERENCE_API_URL || "http://localhost:8000";

export async function POST(request: Request) {
  try {
    const body = await request.json();
    const angles = body.angles;

    if (!angles || !Array.isArray(angles)) {
      return NextResponse.json({ error: "Invalid angles array" }, { status: 400 });
    }

    const response = await fetch(`${API_URL}/infer`, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ angles }),
    });

    if (!response.ok) {
      throw new Error(`API error: ${response.status}`);
    }

    const result = await response.json();
    return NextResponse.json(result);
  } catch (error) {
    console.error("Inference error:", error);
    return NextResponse.json(
      { error: "Inference failed - make sure API server is running" },
      { status: 500 }
    );
  }
}

export async function GET() {
  try {
    const response = await fetch(`${API_URL}/health`);
    const data = await response.json();
    return NextResponse.json(data);
  } catch {
    return NextResponse.json(
      { status: "unhealthy", error: "API server not running" },
      { status: 503 }
    );
  }
}