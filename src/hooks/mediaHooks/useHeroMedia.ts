import { useEffect, useMemo, useState } from "react";
import axios from "axios";
import { useTMDBQuery } from "../tmdbHooks/useTMDBQuery";
import { normalizeMovie, normalizeShow } from "../../utils/normalizeTMDB";
import type { TMDBRawMovie } from "../../types/TMDBMovieType";
import type { TMDBRawShow } from "../../types/TMDBShowType";
import type { TMDBMedia } from "../../types/TMDBMediaType";
import type { UseQueryResult } from "@tanstack/react-query";

interface TMDBMultiItem extends Partial<TMDBRawMovie>, Partial<TMDBRawShow> {
  media_type: "movie" | "tv" | "person";
}

interface TMDBMultiResponse {
  results: TMDBMultiItem[];
}

type UseHeroMediaResult = UseQueryResult<TMDBMultiResponse> & {
  heroes: TMDBMedia[]
}

export const useHeroMedia = (
  count: number = 20
): UseHeroMediaResult => {

  const query =
    useTMDBQuery<TMDBMultiResponse>({
      endpoint: "/trending/all/day"
    });

  const baseHeroes = useMemo(() => {
    const items = query.data?.results ?? [];

    const filtered = items.filter(
      x =>
        (x.media_type === "movie" || x.media_type === "tv") &&
        x.backdrop_path
    );

    const normalized: TMDBMedia[] = filtered.map(x =>
      x.media_type === "movie"
        ? normalizeMovie(x as TMDBRawMovie)
        : normalizeShow(x as TMDBRawShow)
    );

    return normalized.slice(0, count);

  }, [query, count]);

  const [heroes, setHeroes] = useState<TMDBMedia[]>([]);

  useEffect(() => {
    if (!baseHeroes.length) return;

    let cancelled = false;

    const loadLogos = async () => {
      const withLogos = await Promise.all(
        baseHeroes.map(async (m) => {
          try {
            const resp = await axios.get(
              `https://api.themoviedb.org/3/${m.mediaType}/${m.id}/images`,
              {
                params: {
                  api_key: import.meta.env.VITE_TMDB_API_KEY
                }
              }
            );

            const logos = resp.data?.logos ?? [];
            const logo = logos.find((l : any) => l.iso_639_1 === "en") || logos[0];

            return {
              ...m,
              logo_path: logo
                ? `${logo.file_path}`
                : undefined
            };

          } catch {
            return { ...m, logoUrl: undefined };
          }
        })
      );

      if (!cancelled) setHeroes(withLogos);
    };

    loadLogos();

    return () => { cancelled = true };

  }, [baseHeroes]);

  return {
    ...query,
    heroes: heroes
  }
};
