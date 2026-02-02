import "./MediaLayout.css"
import type { TMDBMedia } from "../../../types/TMDBMediaType";
import { Trailer } from "../../ui/Trailer/Trailer";
import type { TMediaType } from "../../../types/genericTypes";
import { useSearchParams } from "react-router-dom";
import { Icon } from "../../ui/Icon/Icon";
import { FaLongArrowAltLeft } from "react-icons/fa";

interface Props {
    media: TMDBMedia;
    isLoading: boolean;
    error: Error | null;
    mediaType: TMediaType;
    children?: React.ReactNode;
}

export const MediaLayout = ({media, isLoading, error, mediaType, children} : Props) => {
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

    if(isLoading || !media) {
        return <div className="loading"></div>
    }
    return (
        <div className={`media-layout media-page ${mediaType}`}>
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
             <div className={`player`}>
                <Icon Icon={FaLongArrowAltLeft} onClick={cancelPlay}/>
                <iframe 
                    src={getMediaSrc()} 
                    allowFullScreen
                />
            </div>
           }
            <div className="media-layout-content">
                {children}
            </div>
        </div>
    )
}