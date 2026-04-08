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


export const getInitials = (name?: string) => {
    if (!name) return "";

    const parts = name.trim().split(" ");

    if (parts.length === 1) {
        return parts[0][0].toUpperCase();
    }

    return (
        parts[0][0] + parts[parts.length - 1][0]
    ).toUpperCase();
};

type Format = "short" | "full";

export const timeAgo = (
    timestamp: string | number | Date,
    format: Format = "short"
): string => {
    const now = new Date();
    const past = new Date(timestamp);
    const diffInSeconds = Math.floor((now.getTime() - past.getTime()) / 1000);

    const formatUnit = (
        value: number,
        short: string,
        full: string
    ) => {
        if (format === "short") return `${value}${short}`;
        return `${value} ${full}${value !== 1 ? "s" : ""} ago`;
    };

    if (diffInSeconds < 60) {
        return formatUnit(diffInSeconds, "s", "second");
    }

    const minutes = Math.floor(diffInSeconds / 60);
    if (minutes < 60) return formatUnit(minutes, "m", "minute");

    const hours = Math.floor(minutes / 60);
    if (hours < 24) return formatUnit(hours, "h", "hour");

    const days = Math.floor(hours / 24);
    if (days < 7) return formatUnit(days, "d", "day"); 

    const weeks = Math.floor(days / 7);
    if (weeks < 4) return formatUnit(weeks, "w", "week");

    const months = Math.floor(days / 30);
    if (months < 12) return formatUnit(months, "mo", "month");

    const years = Math.floor(days / 365);
    return formatUnit(years, "y", "year");
};

export const cleanFirestoreData = (obj: any): any => {
    return Object.fromEntries(
        Object.entries(obj)
            .filter(([_, v]) => v !== undefined)
            .map(([k, v]) => [
                k,
                typeof v === "object" && v !== null && !Array.isArray(v)
                    ? cleanFirestoreData(v)
                    : v
            ])
    );
};