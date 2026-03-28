import { useMemo } from "react";
import type { TMDBRawMovie } from "../../../types/TMDBMovieType";
import { useTMDBQuery } from "../tmdbHooks/useTMDBQuery"
import { type TMDBMedia, type TMDBMovieMedia } from "../../../types/TMDBMediaType";
import { normalizeMovie } from "../../../utils/normalizeTMDB";
import type { UseQueryResult } from "@tanstack/react-query";

interface TMDBCollectionResponse {
    id: number;
    name: string;
    overview: string;
    parts: TMDBRawMovie[];
    poster_path: string;
    backdrop_path: string;
}
type UseMovieResult = UseQueryResult<TMDBCollectionResponse> & {
    overview: string;
    movies: TMDBMovieMedia[];
    seriesPosterPath: string;
    seriesBackdropPath: string;
}

export const useMovieCollection = (collectionId : number) : UseMovieResult => {
    const query = useTMDBQuery<TMDBCollectionResponse>({
        endpoint: `/collection/${collectionId}`,
        params: {
            language: "en-US",
        },
        enabled: !!collectionId
    })
    const movies = useMemo<TMDBMovieMedia[]>(() => {
        if(!query.data?.parts) return [];

        return query.data.parts
            .filter((m) => Boolean(m.backdrop_path))
            .map((m) => normalizeMovie(m))
    }, [query.data?.parts])
    // const { data, ...queryWithoutData } = query
    return {
        ...query,
        overview: query.data?.overview ?? "",
        movies,
        seriesBackdropPath: query.data?.backdrop_path ?? "",
        seriesPosterPath: query.data?.poster_path ?? ""
    }
}