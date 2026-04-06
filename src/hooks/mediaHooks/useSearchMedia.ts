import { useMemo, useState } from "react"
import { useTMDBQuery } from "./tmdbHooks/useTMDBQuery"
import type { TMDBListResponse, TMDBMediaQueryResult, TMediaType } from "../../types/tmdb"
import { normalizeTMDBMedia } from "../../utils/normalizeTMDB"

type MediaSearchQueryResult = TMDBMediaQueryResult & {
    search: string
    setSearch: React.Dispatch<React.SetStateAction<string>>
    executeSearch: (term?: string) => void
    hasSearched: boolean
}

export const useSearchMedia = (
    mediaType: TMediaType | "multi"
): MediaSearchQueryResult => {
    
    const [bufferedSearch, setBufferedSearch] = useState("")
    const [searchQuery, setSearchQuery] = useState("")
    const [hasSearched, setHasSearched] = useState(false)

    const executeSearch = (term?: string) => {
        const final = (term ?? bufferedSearch).trim()

        if (!final) {
            setHasSearched(false);
            return
        }

        // 🟢 Prevent duplicate searches
        if (final === searchQuery) return

        setSearchQuery(final)
        setHasSearched(true)
    }

    const query = useTMDBQuery<TMDBListResponse>({
        endpoint: `/search/${mediaType}`,
        params: {
            query: searchQuery,
            page: 1
        },
        enabled: !!searchQuery
    })

    const media = useMemo(() => {
        const results = query.data?.results || []

        return normalizeTMDBMedia(results, {
            defaultMediaType: mediaType === "movie" ? "movie" : "tv"
        })
    }, [query.data?.results, mediaType])

    return {
        ...query,
        media,
        search: bufferedSearch,
        setSearch: setBufferedSearch,
        executeSearch,
        hasSearched
    }
}