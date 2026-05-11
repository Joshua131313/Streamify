import { useTMDBQuery } from "./useTMDBQuery";

export const useMediaVideos = (
    mediaType: "movie" | "tv",
    id?: number,
    enabled = true
) => {

    return useTMDBQuery({
        endpoint: `/${mediaType}/${id}/videos`,
        enabled: !!id && enabled
    });
};