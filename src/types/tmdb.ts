import type { UseQueryResult } from "@tanstack/react-query";
import type { TMDBMedia, TMDBRawMedia } from "./TMDBMediaType";
import type { TMDB_IMAGE_SIZES } from "../data";

export type TStreamCategories = "top10" | "trending" | "top_rated" | "byGenre" | "provider" ;

export type TStreamProviders = "netflix" | "prime" | "max" | "disney" | "appletv" | "paramount"

export type TMediaType = "movie" | "tv"| "person";

export type TRailVariant = "normal" | "top10"

export interface TMDBListResponse {
  results: TMDBRawMedia[];
}
export type MediaListQueryResult =
  TMDBMediaQueryResult<TMDBListResponse>;

export type TMDBMediaQueryResult<TData = unknown> =
  UseQueryResult<TData> & {
    media: TMDBMedia[];
};
export type TLabelValue = {
    label: string;
    value: string;
}  

export type TMDBImageType = keyof typeof TMDB_IMAGE_SIZES;

export type TMDBImageSize<T extends TMDBImageType> =
  (typeof TMDB_IMAGE_SIZES)[T][number];