import type { TMediaType } from "./tmdb";
import type { TMDBLogo, TMDBMediaCredits, TMDBMovieMedia, TMDBVideo } from "./TMDBMediaType";

export type TMDBRawMovie = {
  adult: boolean;
  backdrop_path: string | null;
  genre_ids?: number[];
  genres?: { id: number; name: string }[]; 
  id: number;
  original_language: string;
  original_title: string;
  overview: string;
  popularity: number;
  poster_path: string | null;
  release_date: string; 
  title: string;
  video?: boolean;
  vote_average: number;
  vote_count: number;
  media_type: TMediaType;

  budget?: number;
  homepage?: string | null;
  imdb_id?: string | null;
  production_companies?: {
    id: number;
    logo_path: string | null;
    name: string;
    origin_country: string;
  }[];
  production_countries?: {
    iso_3166_1: string;
    name: string;
  }[];
  revenue?: number;
  runtime?: number | null;
  spoken_languages?: {
    iso_639_1: string;
    english_name: string;
    name: string;
  }[];
  status?: string;
  tagline?: string | null;
  videos?: {
    results: TMDBVideo[];
  };
  images?: {
    logos: TMDBLogo[]
  };
  credits?: TMDBMediaCredits;
};
export const TMDBNullMovie: TMDBRawMovie = {
  adult: false,
  backdrop_path: null,
  genre_ids: [],
  genres: [],
  id: 0,
  original_language: "",
  original_title: "",
  overview: "",
  popularity: 0,
  poster_path: null,
  release_date: "",
  title: "",
  video: false,
  vote_average: 0,
  vote_count: 0,

  budget: 0,
  homepage: null,
  imdb_id: null,
  production_companies: [],
  production_countries: [],
  revenue: 0,
  runtime: null,
  spoken_languages: [],
  status: "",
  tagline: null,
  media_type: "movie"
};
