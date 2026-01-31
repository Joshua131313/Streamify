import "./MediaLayout.css"
import type { TMDBMedia } from "../../../types/TMDBMediaType";
import { Trailer } from "../../ui/Trailer/Trailer";
import type { TMediaType } from "../../../types/genericTypes";

interface Props {
    media: TMDBMedia;
    mediaType: TMediaType;
    children?: React.ReactNode;
}

export const MediaLayout = ({media, mediaType, children} : Props) => {
    
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
            <div className="media-layout-content">
                {children}
            </div>
        </div>
    )
}