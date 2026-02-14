// import { useMemo, useState, useEffect } from "react";
// import axios from "axios";
// import { useTMDBQuery } from "./tmdbHooks/useTMDBQuery";
// import type { TMDBListResponse, TMDBMediaQueryResult, TMediaType } from "../../types/tmdb";
// import { normalizeTMDBMedia } from "../../utils/normalizeTMDB";
// import type { SearchType } from "../../pages/Search/Search";

// type AIParams = {
//   mediaType?: "movie" | "tv" | "both";
//   with_genres?: number[];
//   sort_by?: string;
//   vote_count_gte?: number;
//   year_gte?: number;
// };

// type MediaSearchQueryResult = TMDBMediaQueryResult & {
//   search: string;
//   setSearch: React.Dispatch<React.SetStateAction<string>>;
//   executeSearch: () => void;
// };

// export const useSearchMedia = (
//   mediaType: TMediaType | "multi",
//   searchType: SearchType
// ): MediaSearchQueryResult => {
//   const [bufferedSearch, setBufferedSearch] = useState("");
//   const [search, setSearch] = useState("");

//   const [aiParams, setAIParams] = useState<AIParams | null>(null);

//   const executeSearch = () => {
//     setSearch(bufferedSearch);
//   };

//   /**
//    * =========================
//    * 1️⃣ CALL AI WHEN NEEDED
//    * =========================
//    */
//   useEffect(() => {
//     if (searchType !== "ai" || !search) return;

//     const runAI = async () => {
//       try {
//         const res = await axios.post("/api/ai-search", { prompt: search });
//         setAIParams(res.data);
//       } catch (err) {
//         console.error("AI search failed:", err);
//         setAIParams(null);
//       }
//     };

//     runAI();
//   }, [search, searchType]);

//   /**
//    * =========================
//    * 2️⃣ REGULAR TMDB SEARCH
//    * =========================
//    */
//   const regularQuery = useTMDBQuery<TMDBListResponse>({
//     endpoint: `/search/${mediaType}`,
//     params: { query: search, page: 1 },
//     enabled: searchType === "regular" && !!search,
//   });

//   /**
//    * =========================
//    * 3️⃣ AI TMDB DISCOVER QUERY
//    * =========================
//    */
//   const aiQuery = useTMDBQuery<TMDBListResponse>({
//     endpoint:
//       aiParams?.mediaType === "tv"
//         ? "/discover/tv"
//         : "/discover/movie",
//     params: {
//       with_genres: aiParams?.with_genres?.join(","),
//       sort_by: aiParams?.sort_by ?? "popularity.desc",
//       "vote_count.gte": aiParams?.vote_count_gte,
//       ...(aiParams?.year_gte && {
//         [aiParams.mediaType === "tv"
//           ? "first_air_date.gte"
//           : "primary_release_date.gte"]: `${aiParams.year_gte}-01-01`,
//       }),
//     },
//     enabled: searchType === "ai" && !!aiParams,
//   });

//   console.log("ai", aiQuery.data?.results)
//   /**
//    * =========================
//    * 4️⃣ PICK ACTIVE QUERY
//    * =========================
//    */
//   const activeQuery = searchType === "ai" ? aiQuery : regularQuery;

//   /**
//    * =========================
//    * 5️⃣ NORMALIZE MEDIA
//    * =========================
//    */
//   const media = useMemo(() => {
//     const results = activeQuery.data?.results || [];

//     return normalizeTMDBMedia(results, {
//       defaultMediaType:
//         mediaType === "movie" ? "movie" : "tv",
//     });
//   }, [activeQuery.data?.results, mediaType]);

//   return {
//     ...activeQuery,
//     media,
//     search: bufferedSearch,
//     setSearch: setBufferedSearch,
//     executeSearch,
//   };
// };
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
export const useSearchMedia = (mediaType: TMediaType | "multi") : MediaSearchQueryResult => {
    const [bufferedSearch, setBufferedSearch] = useState<string>("")
    const [search, setSearch] = useState<string>("");
    const executeSearch = () => {
        setSearch(bufferedSearch)
    }
    const query = useTMDBQuery<TMDBListResponse>({
        endpoint: `/search/${mediaType}`,
        params: {
            query: search,
            page: 1
        },
        enabled: !!search
    })
    const media = useMemo(() => {
        const results = query.data?.results || [];
        return normalizeTMDBMedia(results, {defaultMediaType: mediaType === "movie" ? "movie" : "tv"});
    }, [query.data?.results]);
    
    return {
        ...query,
        media,
        search: bufferedSearch, 
        setSearch: setBufferedSearch,
        executeSearch
    }
}