import type { TMDBRawMovie } from "./TMDBMovieType";
import type { TMDBRawShow } from "./TMDBShowType";

export interface TMDBLogo {
    aspect_ratio: number;
    file_path: string;
    height: number;
    iso_639_1: string;
    iso_3166_1: string;
    vote_average: number;
    vote_count: number;
    width: number;
}
export interface TMDBVideo {
    key: string;
    type: string;
    site: string;
    official: boolean;
}
interface TMDBPersn {
  adult: boolean;
  profile_path: string;
  popularity: number;
  original_name: string;
  name: string;
  known_for_department: string;
  id: number;
  gender: number;
  credit_id: string;
  place_of_birth: string;
  birthday: string;
  biography: string;
}
export interface TMDBCrewPerson extends TMDBPersn {
  department: string;
  job: string;
}
export interface TMDBCastPerson  extends TMDBPersn{
  cast_id: number;
  character: string;
}
export type TMDBPersonCredit = TMDBCastPerson | TMDBCrewPerson;
export interface TMDBMediaCredits {
  cast: TMDBCastPerson[];
  crew: TMDBCrewPerson[];
}

type TMDBMediaBase = {
  adult: boolean;
  backdrop_path: string | null;
  genre_ids?: number[];
  genres?: { id: number; name: string }[];
  id: number;

  original_language: string;
  overview: string;
  popularity: number;
  poster_path: string | null;

  vote_average: number;
  vote_count: number;

  // unified convenience fields
  title: string;
  original_title: string;
  date: string;
  videos?: TMDBVideo[];
  credits?: TMDBMediaCredits;
  logo_path?: string;
};

export type TMDBMovieMedia = TMDBMediaBase & {
  mediaType: "movie";

  // movie-only
  video?: boolean;
  release_date?: string;

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
};
export type TMDBShowMedia = TMDBMediaBase & {
  mediaType: "tv";

  // tv-only
  origin_country?: string[];
  original_name?: string;
  first_air_date?: string;

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
  seasons?: {
    air_date: string | null;
    episode_count: number;
    id: number;
    name: string;
    overview: string;
    poster_path: string | null;
    season_number: number;
  }[];
  status?: string;
  tagline?: string | null;
  type?: string;
  production_companies?: {
    id: number;
    logo_path: string | null;
    name: string;
    origin_country: string;
  }[];
};
export type TMDBMedia = TMDBMovieMedia | TMDBShowMedia;
export type TMDBRawMedia = TMDBRawMovie | TMDBRawShow;
