import axios from "axios";
import { useEffect, useState } from "react";

interface TMDBQueryProps {
    endpoint: string;
    params?: Record<string, any>;
}

export const useTMDBQuery = <T = any>(
  { endpoint, params }: TMDBQueryProps
): [T | null, boolean, any] => {
    
    const [data, setData] = useState<T | null>(null);
    const [loading, setLoading] = useState(false);
    const [error, setError] = useState<any>(null);

    useEffect(()=> {
        let cancelled = false;
        setLoading(true);
        setError(null);

        axios.get(`https://api.themoviedb.org/3${endpoint}`, {
            params: {
                api_key: import.meta.env.VITE_TMDB_API_KEY,
                ...params
            }
        })
        .then((res) => {
            if(!cancelled) setData(res.data);
        })
        .catch(setError)
        .finally(() => {
            if(!cancelled) setLoading(false)
        })
        return () => { cancelled = true };
    }, [endpoint, JSON.stringify(params)])

    return [data, loading, error];
}