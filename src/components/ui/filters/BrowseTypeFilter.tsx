import type { TLabelValue } from "../../../types/tmdb";
import { UrlSelectFilter } from "./UrlSearchFilter";

const browseTypeOptions: TLabelValue[] = [
  { value: "", label: "Browse" },
  { value: "movie-series", label: "Movie Series" },
];

export const BrowseTypeFilter = () => {
  return (
    <UrlSelectFilter
      param="browseType"
      options={browseTypeOptions}
      defaultOption={browseTypeOptions[0]}
    />
  );
};
