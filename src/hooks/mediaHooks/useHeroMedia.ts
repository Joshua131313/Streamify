import { useEffect, useState } from "react";
import axios from "axios";
import { useMixedMedia } from "./useMixedMedia";
import type { TMDBMedia } from "../../types/TMDBMediaType";
import type { TMDBMediaQueryResult } from "../../types/tmdb";

export const useHeroMedia = (
  count: number = 8
): TMDBMediaQueryResult => {

  const mixed = useMixedMedia("/trending/all/day", count);
  const [heroes, setHeroes] = useState<TMDBMedia[]>([]);

  useEffect(() => {
    if (!mixed.media.length) return;

    let cancelled = false;

    const loadLogos = async () => {
      const withLogos = await Promise.all(
        mixed.media.map(async (m) => {
          try {
            const resp = await axios.get(
              `https://api.themoviedb.org/3/${m.mediaType}/${m.id}/images`,
              {
                params: {
                  api_key: import.meta.env.VITE_TMDB_API_KEY,
                },
              }
            );

            const logos = resp.data?.logos ?? [];
            const logo =
              logos.find((l: any) => l.iso_639_1 === "en") || logos[0];

            return {
              ...m,
              logo_path: logo ? logo.file_path : undefined,
            };
          } catch {
            return { ...m, logo_path: undefined };
          }
        })
      );

      if (!cancelled) setHeroes(withLogos);
    };

    loadLogos();
    return () => {
      cancelled = true;
    };
  }, [mixed.media]);

  return {
    ...mixed,
    media: heroes,
  };
};
