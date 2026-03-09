import { useQuery } from "@tanstack/react-query";
import axios from "axios";
import { type TMDBPersonCredit } from "../../../types/TMDBMediaType";

const API_KEY = import.meta.env.VITE_TMDB_API_KEY;
const BASE = "https://api.themoviedb.org/3";

export const usePerson = (personId: string) => {
    return useQuery<TMDBPersonCredit>({
        queryKey: ["person", personId],
        queryFn: async () => {
            const { data } = await axios.get(
                `${BASE}/person/${personId}?api_key=${API_KEY}`
            );
            return data;
        },
        enabled: !!personId,
    });
};