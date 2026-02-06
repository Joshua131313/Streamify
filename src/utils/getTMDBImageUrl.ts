import { TMDB_IMAGE_BASE_URL, TMDB_IMAGE_SIZES } from "../data";
import type { TMDBImageSize, TMDBImageType } from "../types/tmdb";

export const getTMDBImageUrl = <T extends TMDBImageType>(
  type: T,
  path?: string,
  size?: TMDBImageSize<T>
) => {
  if (!path) return "";

  const finalSize = size ?? TMDB_IMAGE_SIZES[type][0];

  return `${TMDB_IMAGE_BASE_URL}${finalSize}${path}`;
};
