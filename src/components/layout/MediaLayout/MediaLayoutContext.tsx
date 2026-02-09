import { createContext, useContext } from "react"
import type { TMDBMedia } from "../../../types/TMDBMediaType";
import type { TMediaType } from "../../../types/tmdb";

interface MediaLayoutState {
    media: TMDBMedia;
    mediaType: TMediaType;
}
interface MediaLayoutProviderProps {
    media: TMDBMedia;
    mediaType: TMediaType;
    children: React.ReactNode;
}
const MediaLayoutContext = createContext<MediaLayoutState | null>(null)

export const MediaLayoutProvider = (props : MediaLayoutProviderProps) => {

    const { media, mediaType, children } = props;

    return (
        <MediaLayoutContext.Provider
            value={{
                media,
                mediaType
            }}
        >
            {children}
        </MediaLayoutContext.Provider>
    )
}

export const useMediaLayoutContext = () => {
    const ctx = useContext(MediaLayoutContext);
    if(!ctx) throw new Error("useMediaLayoutContext must be used inside MediaLayoutProvider");
    return ctx;
}