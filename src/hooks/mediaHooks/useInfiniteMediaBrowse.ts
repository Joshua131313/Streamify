
import { useInfiniteQuery } from "@tanstack/react-query";
import { useSearchParams } from "react-router-dom";
import { TMDB_MEDIA_GENRES } from "../../data/TMDBGenres";
import { normalizeTMDBMedia } from "../../utils/normalizeTMDB";
import axios from "axios";

export const useInfiniteMediaBrowse = () => {
  const [searchParams] = useSearchParams();

  const mediaType = (searchParams.get("media") ?? "movie") as
    | "movie"
    | "tv";

  const urlGenre = searchParams.get("genre");

  const genre =
    TMDB_MEDIA_GENRES.find(x => x.value === urlGenre) ?? null;

  const query = useInfiniteQuery({
    queryKey: ["browse", mediaType, urlGenre],
    initialPageParam: 1,
    queryFn: async ({ pageParam = 1 }) => {
      const params: Record<string, any> = {
        page: pageParam,
        with_origin_country: "US",
      };

      if (genre?.value) {
        params.with_genres = genre.value;
      }

      const res = await axios.get(
        `https://api.themoviedb.org/3/discover/${mediaType}`,
        {
          params: {
            api_key: import.meta.env.VITE_TMDB_API_KEY,
            ...params,
          },
        }
      );

      return res.data;
    },

    getNextPageParam: (lastPage, pages) => {
      if (pages.length < lastPage.total_pages) {
        return pages.length + 1;
      }
      return undefined;
    },
  });

  const media =
    query.data?.pages
      .flatMap(p => p.results)
      .map(item => ({ ...item, media_type: mediaType })) ?? [];

  return {
    ...query,
    media: normalizeTMDBMedia(media),
    genre,
  };
};
