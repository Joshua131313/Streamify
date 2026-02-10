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
    const media = useMemo(() => {
        const results = query.data?.results || [];
        return normalizeTMDBMedia(results, {defaultMediaType: searchType === "movie" ? "movie" : "tv"});
    }, [query.data?.results]);
    
    return {
        ...query,
        media,
        search: bufferedSearch, 
        setSearch: setBufferedSearch,
        executeSearch
    }
}