import { useMemo, useState } from "react"
import { useTMDBQuery } from "./tmdbHooks/useTMDBQuery";
import type { TMDBMedia, TMDBRawMedia } from "../../types/TMDBMediaType";
import type { TMDBListResponse, TMDBMediaQueryResult, TMediaType } from "../../types/tmdb.ts";
import { normalizeTMDBMedia } from "../../utils/normalizeTMDB.ts";


type MediaSearchQueryResult = TMDBMediaQueryResult & {
    search: string;
    setSearch: React.Dispatch<React.SetStateAction<string>>;
    executeSearch: () => void;
}
export const useSearchMedia = (searchType: TMediaType | "multi") : MediaSearchQueryResult => {
    const [bufferedSearch, setBufferedSearch] = useState<string>("")
    const [search, setSearch] = useState<string>("");
    const executeSearch = () => {
        setSearch(bufferedSearch)
    }
    const query = useTMDBQuery<TMDBListResponse>({
        endpoint: `/search/${searchType}`,
        params: {
            query: search,
            page: 1
        },
        enabled: !!search
    })
    const inferredMediaType = searchType === "movie" || searchType === "tv" ? searchType : undefined;
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
        search: bufferedSearch, 
        setSearch: setBufferedSearch,
        executeSearch
    }
}