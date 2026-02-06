import type { TLabelValue } from "../types/tmdb";
export type TSortConfig = {
  sort_by: string;
  date_lte?: string; // key name depends on media type
};

export const sortMap: {
  movie: Record<string, TSortConfig>;
  tv: Record<string, TSortConfig>;
} = {
  movie: {
    year: {
      sort_by: "primary_release_date.desc",
      date_lte: "primary_release_date.lte",
    },
    "title-asc": {
      sort_by: "original_title.asc",
    },
    "title-desc": {
      sort_by: "original_title.desc",
    },
  },
  tv: {
    year: {
      sort_by: "first_air_date.desc",
      date_lte: "first_air_date.lte",
    },
    "title-asc": {
      sort_by: "name.asc",
    },
    "title-desc": {
      sort_by: "name.desc",
    },
  },
};

export const ORDER_BY_OPTIONS : TLabelValue[] = [
    {
        label: "Year released",
        value: "year"
    },
    {
        label: "A-Z",
        value: "title-asc"
    },
    {
        label: "Z-A",
        value: "title-desc"
    }
]
export const TMDB_IMAGE_SIZES = {
  backdrop: ["w300", "w780", "w1280", "original"],
  logo: ["w45", "w92", "w154", "w185", "w300", "w500", "original"],
  poster: ["w92", "w154", "w185", "w342", "w500", "w780", "original"],
  profile: ["w45", "w185", "h632", "original"],
  still: ["w92", "w185", "w300", "original"],
} as const;

export const TMDB_IMAGE_BASE_URL = "https://image.tmdb.org/t/p/";
