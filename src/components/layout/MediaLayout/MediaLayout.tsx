import "./MediaLayout.css"
import type { TMDBMedia } from "../../../types/TMDBMediaType";
import { Trailer } from "../../ui/Trailer/Trailer";
import type { TMediaType } from "../../../types/tmdb";
import { useSearchParams } from "react-router-dom";
import { Icon } from "../../ui/Icon/Icon";
import { FaLongArrowAltLeft } from "react-icons/fa";
import { useEffect } from "react";
import { RecommendationMedia } from "../../media/RecommendationMedia/RecommendationMedia";
import { Actors } from "../../media/Actors/Actors";
import { createPortal } from "react-dom";
import { MediaPlayer } from "../../media/MediaPlayer/MediaPlayer";

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
        return <div className="loading"></div>
    }
    return (
        <div className={`media-layout media-page ${mediaType}`} id={containerId}>
            <Trailer 
                logo_path={media?.logo_path ?? ""}
                trailer_id={media?.videos?.find(x=> x.official && x.type === "Trailer" && x.site === "YouTube")?.key ?? ""}
                backdrop_path={media?.backdrop_path ?? ""}
                mediaMetaBadgesProps={{
                    date: media?.date ?? "",
                    genre_ids: media?.genres?.map(g => g.id) ?? [],
                    vote_average: media?.vote_average ?? 0,
                }}
                description={media?.overview ?? ""}
                mediaId={media?.id ?? 0}
                mediaType={mediaType}
            />
           {
            shouldPlay && 
            <MediaPlayer 
                media={media} 
                mediaType={mediaType}
            />
           }
            <div className="media-layout-content">
                {children}
            </div>
            <Actors 
                actors={media.credits?.cast}
            />
            <RecommendationMedia 
                mediaType={mediaType}
                mediaId={media.id}
            />
        </div>
    )
}