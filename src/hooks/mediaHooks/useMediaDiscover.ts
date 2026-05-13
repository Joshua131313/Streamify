import { useMemo } from "react";
import { useTMDBQuery } from "./tmdbHooks/useTMDBQuery";
import { normalizeMovie, normalizeShow } from "../../utils/normalizeTMDB";
import type { TMDBRawMovie } from "../../types/TMDBMovieType";
import type { TMDBRawShow } from "../../types/TMDBShowType";
import type { TMDBMedia } from "../../types/TMDBMediaType";
import type {
  TMDBListResponse,
  TMDBMediaQueryResult,
  TMediaTypeSelect,
  TStreamCategories,
  TStreamProviders
} from "../../types/tmdb";
import { providers } from "../../data/providers";
import { useAuthProvider } from "../../context/AuthContext";
import { useWatchHistoryContext } from "../../context/WatchHistoryContext";
import { TMDB_GENRES } from "../../data/TMDBGenres";

interface Props {
  mediaType: TMediaTypeSelect;
  category: TStreamCategories;
  genreId?: string;
  provider?: TStreamProviders | "";
  page?: number;
}

type BuildForYouEndpointParams = {
  mediaType: TMediaTypeSelect;
  favoriteGenres?: string[];
  historyGenreIds?: number[];
};

const buildForYouEndpoint = ({
  mediaType,
  favoriteGenres = [],
  historyGenreIds = [],
}: BuildForYouEndpointParams): string => {

  const validGenreSet = new Set(
    TMDB_GENRES
      .filter(g => g.media.includes(mediaType === "all" ? "tv" : mediaType))
      .map(g => Number(g.value))
  );

  const fav = favoriteGenres
    .map(Number)
    .filter(id => validGenreSet.has(id));

  const hist = historyGenreIds
    .filter(id => validGenreSet.has(id));

  const allGenres = [...fav, ...hist];

  if (allGenres.length === 0) {
    return `/trending/${mediaType}/day`;
  }

  const genreCount = new Map<number, number>();

  allGenres.forEach((id) => {
    genreCount.set(id, (genreCount.get(id) || 0) + 1);
  });

  const topGenres = [...genreCount.entries()]
    .sort((a, b) => b[1] - a[1])
    .slice(0, 3)
    .map(([id]) => id);

  if (topGenres.length === 0) {
    return `/trending/${mediaType}/day`;
  }

  return `/discover/${mediaType}?with_genres=${topGenres.join(",")}&sort_by=popularity.desc`;
};
const getEndpoint = ({
  mediaType,
  category,
  genreId,
  provider,
  favoriteGenres,
  historyGenreIds,
}: {
  mediaType: TMediaTypeSelect;
  category: TStreamCategories;
  genreId?: string;
  provider?: TStreamProviders | "";
  favoriteGenres?: string[];
  historyGenreIds?: number[];
}): string => {
  switch (category) {
    case "by_genre":
      return `/discover/${mediaType}?with_genres=${genreId}`;

    case "top_rated":
      return `/${mediaType}/top_rated`;

    case "top_10":
      return `/trending/${mediaType}/week`;

    case "trending":
      return `/trending/${mediaType}/day`;

    case "provider": {
      const providerId = providers.find((x) => x.provider === provider)?.id;
      if (!providerId) return `/trending/${mediaType}/day`;

      return `/discover/${mediaType}?with_watch_providers=${providerId}&watch_region=US&sort_by=popularity.desc`;
    }

    case "for_you":
      return buildForYouEndpoint({
        mediaType,
        favoriteGenres,
        historyGenreIds,
      });

    default:
      return `/trending/${mediaType}/day`;
  }
};

export const useMediaDiscover = ({
  mediaType,
  category,
  genreId,
  provider,
  page = 1,
}: Props): TMDBMediaQueryResult => {
  const { userData } = useAuthProvider();
  const { history } = useWatchHistoryContext();

  const historyGenreIds = useMemo(
    () => history.flatMap((h) => h.genreIds ?? []),
    [history]
  );

  const endpoint = useMemo(() => {
    return getEndpoint({
      mediaType,
      category,
      genreId,
      provider,
      favoriteGenres: userData?.favoriteGenres,
      historyGenreIds,
    });
  }, [mediaType, category, genreId, provider, userData, historyGenreIds]);

  const query = useTMDBQuery<TMDBListResponse>({
    endpoint,
    params: { page },
    enabled: !!endpoint,
  });

  const normalized: TMDBMedia[] = useMemo(() => {
    const results = query.data?.results ?? [];

    return mediaType === "movie"
      ? (results as TMDBRawMovie[]).map(normalizeMovie)
      : (results as TMDBRawShow[]).map(normalizeShow);
  }, [query.data, mediaType]);

  const media = useMemo(() => {
    if (category === "top_10") return normalized.slice(0, 10);
    return normalized;
  }, [normalized, category]);

  return {
    ...query,
    media,
  };
};