import { useMemo } from "react";
import { useTMDBQuery } from "./tmdbHooks/useTMDBQuery";
import { normalizeTMDBMedia } from "../../utils/normalizeTMDB";
import type { TMDBListResponse, TMDBMediaQueryResult } from "../../types/tmdb";

export const useMixedMedia = (
  endpoint: string,
  count: number = 20
): TMDBMediaQueryResult => {

  const query = useTMDBQuery<TMDBListResponse>({
    endpoint,
  });

  const media = useMemo(() => {
    return normalizeTMDBMedia(query.data?.results, count);
  }, [query.data?.results, count]);

  return {
    ...query,
    media,
  };
};
