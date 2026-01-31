import { useParams } from "react-router-dom";
import { useShow } from "../../hooks/showHooks/useShow";
import { Trailer } from "../../components/ui/Trailer/Trailer";

export const Show = ()  => {
    const { showId } = useParams();
    const [show] = useShow({showId: showId!});
    console.log("move", show)
    return (
        <div className="show media-page">
            <Trailer 
                logo_path={show?.logo_path ?? ""}
                trailer_id={show?.videos?.find(x=> x.official && x.type === "Trailer" && x.site === "YouTube")?.key ?? ""}
                backdrop_path={show?.backdrop_path ?? ""}
                mediaMetaBadgesProps={{
                    date: show?.date ?? "",
                    genre_ids: show?.genres?.map(g => g.id) ?? [],
                    vote_average: show?.vote_average ?? 0,
                }}
                description={show?.overview ?? ""}
                mediaId={show?.id ?? 0}
                mediaType="tv"
            />
            <iframe 
                style={{zIndex: 100}}
                src={`https://vidsrc.cc/v3/embed/tv/${showId}`} 
                width="100%" 
                height="600" 
                
                />
        </div>
    )
}