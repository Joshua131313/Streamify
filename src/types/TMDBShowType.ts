import type { TMDBVideo, TMDBMediaCredits, TMDBLogo } from "./TMDBMediaType";
export type TSeason = {
    air_date: string | null;
    episode_count: number;
    id: number;
    name: string;
    overview: string;
    poster_path: string | null;
    season_number: number;
    episodes?: TEpisode[];
}
export interface TEpisode {
  id: number;
  name: string;
  overview: string;
  air_date: string | null;
  episode_number: number;
  season_number: number;
  runtime: number | null;
  still_path: string | null;
  vote_average: number;
  vote_count: number;
}

export type TMDBRawShow = {
  adult: boolean;
  backdrop_path: string | null;
  genre_ids?: number[];
  genres?: { id: number; name: string }[];
  id: number;
  origin_country: string[];
  original_language: string;
  original_name: string;
  overview: string;
  popularity: number;
  poster_path: string | null;
  first_air_date: string; // format: YYYY-MM-DD
  name: string;
  vote_average: number;
  vote_count: number;

  // Detail endpoint extras
  created_by?: {
    id: number;
    credit_id: string;
    name: string;
    gender: number | null;
    profile_path: string | null;
  }[];
  episode_run_time?: number[];
  homepage?: string | null;
  in_production?: boolean;
  languages?: string[];
  last_air_date?: string | null;
  networks?: {
    id: number;
    name: string;
    logo_path: string | null;
    origin_country: string;
  }[];
  number_of_episodes?: number;
  number_of_seasons?: number;
  production_companies?: {
    id: number;
    logo_path: string | null;
    name: string;
    origin_country: string;
  }[];
  seasons?: TSeason[];
  status?: string;
  tagline?: string | null;
  type?: string;
  videos?: {
    results: TMDBVideo[];
  };
  images?: {
    logos: TMDBLogo[]
  };
  credits?: TMDBMediaCredits;
};
export const TMDBNullShow: TMDBRawShow = {
  adult: false,
  backdrop_path: null,
  genre_ids: [],
  genres: [],
  id: 0,
  origin_country: [],
  original_language: "",
  original_name: "",
  overview: "",
  popularity: 0,
  poster_path: null,
  first_air_date: "",
  name: "",
  vote_average: 0,
  vote_count: 0,

  // Detail endpoint extras
  created_by: [],
  episode_run_time: [],
  homepage: null,
  in_production: false,
  languages: [],
  last_air_date: null,
  networks: [],
  number_of_episodes: 0,
  number_of_seasons: 0,
  production_companies: [],
  seasons: [],
  status: "",
  tagline: null,
  type: "",
};
