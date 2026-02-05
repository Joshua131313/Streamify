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