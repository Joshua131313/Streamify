import { useEffect, useMemo, useState } from "react";
import type { TLabelValue, TMDBListResponse, TMDBMediaQueryResult, TMediaType } from "../../types/tmdb";
import { useSearchParams } from "react-router-dom";
import { useTMDBQuery } from "./tmdbHooks/useTMDBQuery";
import { normalizeTMDBMedia } from "../../utils/normalizeTMDB";
import { TMDB_GENRES } from "../../data/TMDBGenres";

type MediaBrowseResult = TMDBMediaQueryResult & {
    genre: TLabelValue | null;
} 



export const useMediaBrowse = (page: number) : MediaBrowseResult => {
    const [searchParams] = useSearchParams();
    const mediaType : TMediaType = (searchParams.get("media") ?? "movie") as TMediaType
    const urlGenre = searchParams.get("genre");

    const genre = TMDB_GENRES.find(x => x.value === urlGenre) ?? null;


    const params: Record<string, any> = {
        page,
        with_origin_country: "US"

    };

    if(genre?.value) {
        params.with_genres = genre.value;
    }


    const query = useTMDBQuery<TMDBListResponse>({
        endpoint: `/discover/${mediaType}`,
        params,
    })

    const media = useMemo(() => {
        const results = query.data?.results || [];
        console.log(results)
        return normalizeTMDBMedia(results);
    }, [query.data?.results]);



    return {
        ...query,
        media,
        genre,
    }
}