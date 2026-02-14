import { providers } from "../data/providers";
import type { TMediaType, TStreamCategories, TStreamProviders } from "../types/tmdb";
import type { TMDBVideo } from "../types/TMDBMediaType";

export const getTMDBEndpointByCategory = (
  type: TMediaType,
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

export const isMobile = () => window.innerWidth < 768;


export const getOfficialYoutubeTrailerId = (videos : TMDBVideo[]) : string => {
  return videos?.find(x=> x.official && x.type === "Trailer" && x.site === "YouTube")?.key ?? ""
}