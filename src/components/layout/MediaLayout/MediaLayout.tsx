import "./MediaLayout.css"
import type { TMDBMedia } from "../../../types/TMDBMediaType";
import { Trailer } from "../../ui/Trailer/Trailer";
import type { TMediaType } from "../../../types/tmdb";
import { useSearchParams } from "react-router-dom";
import { Icon } from "../../ui/Icon/Icon";
import { FaLongArrowAltLeft } from "react-icons/fa";
import { useEffect } from "react";
import { RecommendationMedia } from "../../media/RecommendationMedia/RecommendationMedia";
import { createPortal } from "react-dom";
import { MediaPlayer } from "../../media/MediaPlayer/MediaPlayer";
import { MediaLayoutProvider } from "./MediaLayoutContext";
import { Loader } from "../../ui/Loader/Loader";
import { Crew } from "../../media/Credits/Crew";
import { Cast } from "../../media/Credits/Cast";

interface Props {
    media: TMDBMedia;
    isLoading: boolean;
    error: Error | null;
    mediaType: TMediaType;
    children?: React.ReactNode;
    containerId?: string;
}

export const MediaLayout = ({media, isLoading, error, mediaType, containerId, children} : Props) => {
    const [searchParams] = useSearchParams()
    const shouldPlay = searchParams.has("play");

    if(isLoading || !media) {
        return <Loader fullScreen showLogo={false}/>
    }
    return (
        <MediaLayoutProvider media={media} mediaType={mediaType}>
            <div className={`media-layout media-page ${mediaType}`} id={containerId}>
                <Trailer />
                {
                    shouldPlay && 
                    <MediaPlayer />
                }
                <div className="media-layout-content">
                    {children}
                </div>
                <Crew 
                    crew={media.credits?.crew}
                />
                <Cast 
                    cast={media.credits?.cast}
                />
                <RecommendationMedia 
                    mediaType={mediaType}
                    mediaId={media.id}
                    genre={media?.genres?.[0]?.id ?? 0}
                />
            </div>
        </MediaLayoutProvider>
    )
}