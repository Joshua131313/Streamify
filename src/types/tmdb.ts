import type { UseQueryResult } from "@tanstack/react-query";
import type { TMDBMedia, TMDBRawMedia } from "./TMDBMediaType";

export type TStreamCategories = "top10" | "trending" | "top_rated" | "byGenre" | "provider" ;

export type TStreamProviders = "netflix" | "prime" | "max" | "disney" | "appletv" | "paramount"

export type TMediaType = "movie" | "tv";

export type TMediaRailVariant = "normal" | "top10"

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