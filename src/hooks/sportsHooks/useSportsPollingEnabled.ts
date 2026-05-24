import { useLocation } from "react-router-dom";
import { useMemo } from "react";

export const useSportsPollingEnabled = () => {
    const location = useLocation();

    const isSportsRoute =
        location.pathname.startsWith("/sports");

    const isWatchingSports =
        location.pathname.includes("/provider=") ||
        location.search.includes("league=");

    return useMemo(() => {
        return isSportsRoute && !isWatchingSports;
    }, [isSportsRoute, isWatchingSports]);
};