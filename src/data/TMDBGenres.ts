import type { TLabelValue, TMediaType } from "../types/tmdb";
export type TGenre = {
  label: string;
  value: string;
  media: TMediaType[]; // supports movie, tv, or both
};

export const TMDB_GENRES: TGenre[] = [
  // Movie + TV shared
  { label: "Animation", value: "16", media: ["movie", "tv"] },
  { label: "Comedy", value: "35", media: ["movie", "tv"] },
  { label: "Crime", value: "80", media: ["movie", "tv"] },
  { label: "Documentary", value: "99", media: ["movie", "tv"] },
  { label: "Drama", value: "18", media: ["movie", "tv"] },
  { label: "Family", value: "10751", media: ["movie", "tv"] },
  { label: "Mystery", value: "9648", media: ["movie", "tv"] },
  { label: "Western", value: "37", media: ["movie", "tv"] },

  // Movie-only
  { label: "Action", value: "28", media: ["movie"] },
  { label: "Adventure", value: "12", media: ["movie"] },
  { label: "Fantasy", value: "14", media: ["movie"] },
  { label: "History", value: "36", media: ["movie"] },
  { label: "Horror", value: "27", media: ["movie"] },
  { label: "Music", value: "10402", media: ["movie"] },
  { label: "Romance", value: "10749", media: ["movie"] },
  { label: "Science Fiction", value: "878", media: ["movie"] },
  { label: "TV Movie", value: "10770", media: ["movie"] },
  { label: "Thriller", value: "53", media: ["movie"] },
  { label: "War", value: "10752", media: ["movie"] },

  // TV-only
  { label: "Action & Adventure", value: "10759", media: ["tv"] },
  { label: "Kids", value: "10762", media: ["tv"] },
  { label: "News", value: "10763", media: ["tv"] },
  { label: "Reality", value: "10764", media: ["tv"] },
  { label: "Sci-Fi & Fantasy", value: "10765", media: ["tv"] },
  { label: "Soap", value: "10766", media: ["tv"] },
  { label: "Talk", value: "10767", media: ["tv"] },
  { label: "War & Politics", value: "10768", media: ["tv"] },
];

export const getGenresByMedia = (media: TMediaType | "all") => {
  if (media === "all") return TMDB_GENRES;

  return TMDB_GENRES.filter(g => g.media.includes(media));
};
export const getMainGenres = (media: TMediaType, limit = 7) =>
  getGenresByMedia(media)
    .slice(0, limit)
    .map(({ label, value }) => ({ label, value }));
