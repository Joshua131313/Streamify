import type { TMediaType } from "../types/tmdb";
import type { TMDBMedia, TMDBMovieMedia, TMDBRawMedia, TMDBShowMedia } from "../types/TMDBMediaType";
import type { TMDBRawMovie } from "../types/TMDBMovieType";
import type { TMDBRawShow } from "../types/TMDBShowType";

/* ===========================
   MOVIE NORMALIZER
   =========================== */

export function normalizeMovie(movie: TMDBRawMovie): TMDBMovieMedia {
  const logo = movie.images?.logos?.find(l => l.iso_639_1 === "en") ?? movie.images?.logos?.[0];

  return {
    mediaType: "movie",

    // ─── Common ─────────────────────────────
    adult: movie.adult,
    backdrop_path: movie.backdrop_path,
    genre_ids: movie.genre_ids,
    genres: movie.genres,
    id: movie.id,
    original_language: movie.original_language,
    overview: movie.overview,
    popularity: movie.popularity,
    poster_path: movie.poster_path,
    vote_average: parseFloat(movie.vote_average?.toFixed(1)),
    vote_count: movie.vote_count,

    // ─── Unified convenience fields ─────────
    title: movie.title,
    original_title: movie.original_title,
    date: movie.release_date,
    videos: movie.videos?.results,
    credits: movie.credits,
    // ─── Movie-only ─────────────────────────
    video: movie.video,
    release_date: movie.release_date,

    budget: movie.budget,
    homepage: movie.homepage,
    imdb_id: movie.imdb_id,
    production_companies: movie.production_companies,
    production_countries: movie.production_countries,
    revenue: movie.revenue,
    runtime: movie.runtime,
    spoken_languages: movie.spoken_languages,
    status: movie.status,
    tagline: movie.tagline,
    logo_path: logo
      ?  logo.file_path
    : ""
  };
}

/* ===========================
   TV NORMALIZER
   =========================== */

export function normalizeShow(show: TMDBRawShow): TMDBShowMedia {
  const logo = show.images?.logos?.find(l => l.iso_639_1 === "en") ?? show.images?.logos?.[0];
  return {
    mediaType: "tv",

    // ─── Common ─────────────────────────────
    adult: show.adult,
    backdrop_path: show.backdrop_path,
    genre_ids: show.genre_ids,
    genres: show.genres,
    id: show.id,
    original_language: show.original_language,
    overview: show.overview,
    popularity: show.popularity,
    poster_path: show.poster_path,
    vote_average: parseFloat(show.vote_average?.toFixed(1)),
    vote_count: show.vote_count,

    // ─── Unified convenience fields ─────────
    title: show.name,
    original_title: show.original_name,
    date: show.first_air_date,
    videos: show.videos?.results,
    credits: show.credits,
    // ─── TV-only ────────────────────────────
    origin_country: show.origin_country,
    original_name: show.original_name,
    first_air_date: show.first_air_date,

    created_by: show.created_by,
    episode_run_time: show.episode_run_time,
    homepage: show.homepage,
    in_production: show.in_production,
    languages: show.languages,
    last_air_date: show.last_air_date,
    networks: show.networks,
    number_of_episodes: show.number_of_episodes,
    number_of_seasons: show.number_of_seasons,
    production_companies: show.production_companies,
    seasons: show.seasons ? show.seasons.filter(season => season.season_number > 0) : [],
    status: show.status,
    tagline: show.tagline,
    type: show.type,
    logo_path: logo
      ?   logo.file_path
      : ""
  };
}


export const normalizeTMDBMedia = (
  items: TMDBRawMedia[] = [],
  params?: {
    defaultMediaType?: TMediaType,
    count?: number,
  }
): TMDBMedia[] => {
  const count = params?.count;
  const defaultMediaType = params?.defaultMediaType;
  const filtered = items.filter(
    (x) =>
      (x.media_type !== "person") &&
      Boolean(x.backdrop_path)
  );

  const normalized = filtered.map((x) => {
    if(x.media_type) {
      return x.media_type === "movie"
        ? normalizeMovie(x as TMDBRawMovie)
        : normalizeShow(x as TMDBRawShow)
    }
    else {
      return defaultMediaType === "movie" 
        ? normalizeMovie(x as TMDBRawMovie)
        : normalizeShow(x as TMDBRawShow)
    }
  });

  return typeof count === "number"
    ? normalized.slice(0, count)
    : normalized;
}
