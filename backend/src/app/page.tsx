"use client";

import { useState } from "react";

interface AnomalyResult {
  score: number;
  prediction: number;
  anomaly_strength: number;
  classification: string;
  assistance: number;
  threshold: number;
  floor: number;
}

interface ActivityResult {
  activity: string;
  intention: string;
}

interface InferenceResult {
  anomaly: AnomalyResult;
  activity?: ActivityResult;
  feature_names: string[];
}

const SAMPLE_WINDOWS = {
  "ramp (good)": [45.0, 47.0, 52.0, 58.0, 62.0, 65.0, 63.0, 60.0, 55.0, 50.0],
  "ramp (compensating)": [30.0, 32.0, 35.0, 38.0, 40.0, 42.0, 44.0, 43.0, 42.0, 41.0],
  "levelground": [15.0, 16.0, 17.0, 18.0, 17.0, 16.0, 17.0, 18.0, 17.0, 16.0],
  "stair ascent": [55.0, 60.0, 65.0, 70.0, 75.0, 80.0, 78.0, 75.0, 70.0, 65.0],
};

export default function Home() {
  const [result, setResult] = useState<InferenceResult | null>(null);
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [customAngles, setCustomAngles] = useState("45.0, 47.0, 52.0, 58.0, 62.0, 65.0, 63.0, 60.0, 55.0, 50.0");

  const runInference = async (angles: number[]) => {
    setLoading(true);
    setError(null);
    
    try {
      const response = await fetch("/api/inference", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ angles }),
      });
      
      if (!response.ok) {
        throw new Error(`HTTP ${response.status}: ${response.statusText}`);
      }
      
      const data = await response.json();
      setResult(data);
    } catch (err) {
      setError(err instanceof Error ? err.message : "Unknown error");
      setResult(null);
    } finally {
      setLoading(false);
    }
  };

  const handleSampleClick = (name: string) => {
    const angles = SAMPLE_WINDOWS[name as keyof typeof SAMPLE_WINDOWS];
    if (angles) {
      setCustomAngles(angles.join(", "));
      runInference(angles);
    }
  };

  const handleCustomSubmit = (e: React.FormEvent) => {
    e.preventDefault();
    const angles = customAngles.split(",").map((s) => parseFloat(s.trim())).filter((n) => !isNaN(n));
    if (angles.length > 0) {
      runInference(angles);
    } else {
      setError("Invalid angles format");
    }
  };

  return (
    <div className="min-h-screen bg-zinc-50 dark:bg-black font-sans">
      <main className="max-w-4xl mx-auto py-12 px-6">
        <h1 className="text-3xl font-bold text-center text-zinc-900 dark:text-zinc-50 mb-8">
          ExoMetrix Gait Analysis Demo
        </h1>
        
        <div className="bg-white dark:bg-zinc-900 rounded-lg shadow-md p-6 mb-6">
          <h2 className="text-xl font-semibold mb-4 text-zinc-800 dark:text-zinc-200">
            Test Samples
          </h2>
          <div className="flex flex-wrap gap-2">
            {Object.keys(SAMPLE_WINDOWS).map((name) => (
              <button
                key={name}
                onClick={() => handleSampleClick(name)}
                disabled={loading}
                className="px-4 py-2 bg-blue-600 text-white rounded hover:bg-blue-700 disabled:opacity-50 transition-colors"
              >
                {name}
              </button>
            ))}
          </div>
        </div>
        
        <form onSubmit={handleCustomSubmit} className="bg-white dark:bg-zinc-900 rounded-lg shadow-md p-6 mb-6">
          <h2 className="text-xl font-semibold mb-4 text-zinc-800 dark:text-zinc-200">
            Custom Input
          </h2>
          <div className="flex gap-2">
            <input
              type="text"
              value={customAngles}
              onChange={(e) => setCustomAngles(e.target.value)}
              placeholder="Enter angles (comma separated)"
              className="flex-1 px-4 py-2 border border-zinc-300 dark:border-zinc-700 rounded bg-white dark:bg-zinc-800 text-zinc-900 dark:text-zinc-100"
            />
            <button
              type="submit"
              disabled={loading}
              className="px-6 py-2 bg-green-600 text-white rounded hover:bg-green-700 disabled:opacity-50 transition-colors"
            >
              {loading ? "Loading..." : "Run"}
            </button>
          </div>
        </form>
        
        {error && (
          <div className="bg-red-100 dark:bg-red-900 border border-red-400 text-red-700 dark:text-red-200 px-4 py-3 rounded mb-6">
            {error}
          </div>
        )}
        
        {result && (
          <div className="space-y-6">
            <div className="bg-white dark:bg-zinc-900 rounded-lg shadow-md p-6">
              <h2 className="text-xl font-semibold mb-4 text-zinc-800 dark:text-zinc-200">
                Anomaly Detection
              </h2>
              <div className="grid grid-cols-2 gap-4">
                <div>
                  <p className="text-zinc-600 dark:text-zinc-400">Classification</p>
                  <p className={`text-lg font-semibold ${
                    result.anomaly.classification === "Good step" 
                      ? "text-green-600" 
                      : "text-red-600"
                  }`}>
                    {result.anomaly.classification}
                  </p>
                </div>
                <div>
                  <p className="text-zinc-600 dark:text-zinc-400">Anomaly Strength</p>
                  <p className="text-lg font-semibold text-zinc-900 dark:text-zinc-100">
                    {(result.anomaly.anomaly_strength * 100).toFixed(1)}%
                  </p>
                </div>
                <div>
                  <p className="text-zinc-600 dark:text-zinc-400">Model Score</p>
                  <p className="text-lg font-semibold text-zinc-900 dark:text-zinc-100">
                    {result.anomaly.score.toFixed(4)}
                  </p>
                </div>
                <div>
                  <p className="text-zinc-600 dark:text-zinc-400">Assistance</p>
                  <p className="text-lg font-semibold text-zinc-900 dark:text-zinc-100">
                    {result.anomaly.assistance.toFixed(1)}%
                  </p>
                </div>
              </div>
            </div>
            
            {result.activity && (
              <div className="bg-white dark:bg-zinc-900 rounded-lg shadow-md p-6">
                <h2 className="text-xl font-semibold mb-4 text-zinc-800 dark:text-zinc-200">
                  Activity Recognition
                </h2>
                <div className="grid grid-cols-2 gap-4">
                  <div>
                    <p className="text-zinc-600 dark:text-zinc-400">Activity</p>
                    <p className="text-lg font-semibold text-zinc-900 dark:text-zinc-100">
                      {result.activity.activity}
                    </p>
                  </div>
                  <div>
                    <p className="text-zinc-600 dark:text-zinc-400">Intention</p>
                    <p className="text-lg font-semibold text-zinc-900 dark:text-zinc-100">
                      {result.activity.intention}
                    </p>
                  </div>
                </div>
              </div>
            )}
          </div>
        )}
      </main>
    </div>
  );
}