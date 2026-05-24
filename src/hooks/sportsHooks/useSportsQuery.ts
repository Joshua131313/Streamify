import { useQuery } from "@tanstack/react-query";
import { useSportsPollingEnabled } from "./useSportsPollingEnabled";

interface UseSportsQueryOptions<T> {
    queryKey: string[];
    endpoint: string;
}

export const useSportsQuery = <T>({
    queryKey,
    endpoint,
}: UseSportsQueryOptions<T>) => {

    const pollingEnabled =
        useSportsPollingEnabled();

    const {
        data = [],
        isPending,
        error,
    } = useQuery<T[]>({
        queryKey,

        queryFn: async () => {
            const API_URL =
                import.meta.env.VITE_API_URL || "";

            const res = await fetch(
                `${API_URL}${endpoint}`
            );

            if (!res.ok) {
                throw new Error(
                    `Failed to fetch ${endpoint}`
                );
            }

            return res.json();
        },

        enabled: pollingEnabled,

        refetchInterval:
            pollingEnabled
                ? 30000
                : false,

        refetchOnWindowFocus: false,

        staleTime: 15000,
    });

    return {
        data: Array.isArray(data)
            ? data
            : [],

        isLoading: isPending,

        error,
    };
};