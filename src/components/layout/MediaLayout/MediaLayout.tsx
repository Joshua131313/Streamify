import "./MediaLayout.css"
import type { TMDBMedia } from "../../../types/TMDBMediaType";
import { Trailer } from "../../ui/Trailer/Trailer";
import type { TMediaType } from "../../../types/genericTypes";
import { useSearchParams } from "react-router-dom";
import { Icon } from "../../ui/Icon/Icon";
import { FaLongArrowAltLeft } from "react-icons/fa";

interface Props {
    media: TMDBMedia;
    loading: boolean;
    err: any;
    mediaType: TMediaType;
    children?: React.ReactNode;
}

export const MediaLayout = ({media, loading, err, mediaType, children} : Props) => {
    const [searchParams, setSearchParams] = useSearchParams();
    const shouldPlay = searchParams.has("play");

    const cancelPlay = () => {
        searchParams.delete("play");
        setSearchParams(searchParams, {replace: true});
    }
    console.log("media ", media?.genres?.map(g => g.id))
    if(loading || !media) {
        return <div className="loading"></div>
    }
    console.log("should play", shouldPlay)
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
                    src={`https://vidsrc.cc/v2/embed/${mediaType}/${media.id}`} 
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