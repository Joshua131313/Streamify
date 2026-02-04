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

interface Props {
    media: TMDBMedia;
    isLoading: boolean;
    error: Error | null;
    mediaType: TMediaType;
    children?: React.ReactNode;
    containerId?: string;
}

export const MediaLayout = ({media, isLoading, error, mediaType, containerId, children} : Props) => {
    const [searchParams, setSearchParams] = useSearchParams();
    const shouldPlay = searchParams.has("play");
    
    const cancelPlay = () => {
        searchParams.delete("play");
        searchParams.delete("season");
        searchParams.delete("episode");
        setSearchParams(searchParams, {replace: true});
    }

    const getMediaSrc = () => {
        if(mediaType === "tv") {
            const season = searchParams.get("season");
            const episode = searchParams.get("episode");
            return `https://vidsrc.cc/v3/embed/tv/${media.id}/${season}/${episode}`
        }
        return `https://vidsrc.cc/v3/embed/${mediaType}/${media.id}`
    }
    useEffect(() => {
        if (shouldPlay) {
            const scrollY = window.scrollY;

            document.body.style.position = "fixed";
            document.body.style.top = `-${scrollY}px`;
            document.body.style.width = "100%";
        } else {
            const scrollY = document.body.style.top;

            document.body.style.position = "";
            document.body.style.top = "";
            document.body.style.width = "";

            window.scrollTo(0, parseInt(scrollY || "0") * -1);
        }
        document.body.classList.toggle("player-open", shouldPlay);
        return () => {
            document.body.style.position = "";
            document.body.style.top = "";
            document.body.style.width = "";
            document.body.classList.remove("player-open");
        };
    }, [shouldPlay]);

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
            createPortal(
             <div className={`player`} role="dialog" aria-modal="true">
                <Icon Icon={FaLongArrowAltLeft} onClick={cancelPlay}/>
                <iframe 
                    src={getMediaSrc()} 
                    allowFullScreen
                    onPause={() => console.log("paused")}
                />
            </div>, document.body
            )
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