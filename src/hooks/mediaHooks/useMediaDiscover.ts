import { useTMDBQuery } from "../tmdbHooks/useTMDBQuery";
import { normalizeMovie, normalizeShow } from "../../utils/normalizeTMDB";
import { getTMDBEndpointByCategory } from "../../utils/helpers";
import type { TMDBRawMovie } from "../../types/TMDBMovieType";
import type { TMDBRawShow } from "../../types/TMDBShowType";
import type { TMDBMedia } from "../../types/TMDBMediaType";
import type { TStreamCategories, TStreamProviders } from "../../types/genericTypes";
import type { UseQueryResult } from "@tanstack/react-query";

interface Props {
  mediaType: "movie" | "tv";
  category: TStreamCategories;
  genreId?: string;
  provider?: TStreamProviders | "";
  page?: number;
}
interface TMDBListResponse<T> {
  results: T[];
}

type UseMediaDiscoverResult = UseQueryResult<TMDBListResponse<TMDBRawMovie | TMDBRawShow>> & {
  media: TMDBMedia[]
}

export const useMediaDiscover = (props: Props): UseMediaDiscoverResult => {
  const {
    mediaType,
    category,
    genreId,
    provider,
    page = 1
  } = props;

  const endpoint = getTMDBEndpointByCategory(
    mediaType,
    category,
    genreId,
    provider
  );

  const query = useTMDBQuery<TMDBListResponse<TMDBRawMovie | TMDBRawShow>>({
    endpoint,
    params: { page }
  });

  const results = query.data?.results ?? [];

  const normalized: TMDBMedia[] =
    mediaType === "movie"
      ? (results as TMDBRawMovie[]).map(normalizeMovie)
      : (results as TMDBRawShow[]).map(normalizeShow);

  const final =
    category === "top10"
      ? normalized.slice(0, 10)
      : normalized;

  return {
    ...query,
    media: final
  }
};
