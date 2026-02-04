import { providers } from "../data/providers";
import type { TStreamCategories, TStreamProviders } from "../types/tmdb";

export const getTMDBEndpointByCategory = (
  type: "movie" | "tv",
  category: TStreamCategories,
  genreId?: string,
  provider?: TStreamProviders | ""
) : string => {
  switch (category) {
    case "byGenre":
      return `/discover/${type}?with_genres=${genreId}`;

    case "top_rated":
      return `/${type}/top_rated?`;

    case "top10":
      return `/trending/${type}/week?`;

    case "trending":
      return `/trending/${type}/day?`;

    case "provider":
      const providerId = providers.find((x) => x.provider === provider)?.id;
      return `/discover/${type}?with_watch_providers=${providerId}&watch_region=US&sort_by=popularity.desc`;
    default:
      return ""
  }
};

