import { useEffect, useMemo, useState } from "react";
import type { TLabelValue, TMDBListResponse, TMDBMediaQueryResult, TMediaType } from "../../types/tmdb";
import { useSearchParams } from "react-router-dom";
import { TMDB_MEDIA_GENRES } from "../../data/TMDBGenres";
// import { ORDER_BY_OPTIONS, sortMap } from "../../data";
import { useTMDBQuery } from "./tmdbHooks/useTMDBQuery";
import { normalizeTMDBMedia } from "../../utils/normalizeTMDB";

type MediaBrowseResult = TMDBMediaQueryResult & {
    genre: TLabelValue | null;
    // orderBy: TLabelValue | null;
} 



export const useMediaBrowse = (page: number) : MediaBrowseResult => {
    const [searchParams] = useSearchParams();
    const mediaType : TMediaType = (searchParams.get("media") ?? "movie") as TMediaType
    const urlGenre = searchParams.get("genre");
    // const urlOrderBy = searchParams.get("orderBy");

    const genre = TMDB_MEDIA_GENRES.find(x => x.value === urlGenre) ?? null;

    // const orderBy = ORDER_BY_OPTIONS.find(x => x.value === urlOrderBy) ?? null;

    // build params
    const params: Record<string, any> = {
        page,
        with_origin_country: "US"

    };

    if(genre?.value) {
        params.with_genres = genre.value;
    }
    // if (orderBy) {
    // const config = sortMap[mediaType][orderBy.value];

    // if (config) {
    //     params.sort_by = config.sort_by;

    //     if (config.date_lte) {
    //     const today = new Date().toISOString().split("T")[0];
    //     params[config.date_lte] = today;
    //     }
    // }
    // }


    const query = useTMDBQuery<TMDBListResponse>({
        endpoint: `/discover/${mediaType}`,
        params,
    })

    const inferredMediaType = mediaType === "movie" || mediaType === "tv" ? mediaType : undefined;
    const media = useMemo(() => {
        const results = query.data?.results || [];
        const normalizedInput = inferredMediaType ? 
            results.map((item) => ({...item, media_type: inferredMediaType})) // inject media_type since tmdb will not attach it if searching for specifically movie or tv
            : 
            results
        return normalizeTMDBMedia(normalizedInput);
    }, [query.data?.results]);



    return {
        ...query,
        media,
        genre,
        // orderBy,
    }
}