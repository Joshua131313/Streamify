import { useState } from "react";
import axios from "axios";
import type { TMediaType } from "../../types/tmdb";

type AIParams = {
  mediaType?: TMediaType;
  with_genres?: number[];
  sort_by?: string;
  vote_count_gte?: number;
  year_gte?: number;
};

export const useAISearch = () => {
  const [params, setParams] = useState<AIParams | null>(null);
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const executeAISearch = async (prompt: string) => {
    if (!prompt || prompt.length < 3) return;

    try {
      setLoading(true);
      setError(null);

      const res = await axios.post("/api/ai-search", { prompt });

      setParams(res.data);
    } catch (err: any) {
      console.error("AI search failed:", err);
      setError("AI search failed");
    } finally {
      setLoading(false);
    }
  };

  return {
    params,
    loading,
    error,
    executeAISearch,
  };
};
