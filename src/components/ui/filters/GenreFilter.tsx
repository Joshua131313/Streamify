import type { TMediaType } from "../../../types/tmdb";
import { getGenresByMedia } from "../../../data/TMDBGenres";
import { UrlSelectFilter } from "./UrlSearchFilter";

interface Props {
  mediaType: TMediaType | "all";
  includeAll?: boolean;
}

export const GenreFilter = ({ mediaType, includeAll }: Props) => {
  return (
    <UrlSelectFilter
      param="genre"
      options={getGenresByMedia(mediaType)}
      includeAll={includeAll}
    />
  );
};
