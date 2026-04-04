import { FaChevronRight, FaLongArrowAltLeft } from "react-icons/fa"
import { Icon } from "../../ui/Icon/Icon"
import { createPortal } from "react-dom"
import { useSearchParams } from "react-router-dom"
import { useEffect } from "react"
import "./MediaPlayer.css"
import { YouAreWatching } from "./YouAreWatching"
import { useMediaLayoutContext } from "../../layout/MediaLayout/MediaLayoutContext"
import { useLocalStorage } from "../../../hooks/utilHooks/useLocalStorage"
import { AppPlayer } from "../../ui/AppPlayer/AppPlayer"
import { EpisodeSelector } from "./EpisodeSelector"

export const MediaPlayer = ({ modal = true} : { modal?: boolean}) => {
    const [searchParams, setSearchParams] = useSearchParams();
    const { media, mediaType } = useMediaLayoutContext();
    const { set, upsertShowHistory } = useLocalStorage();
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
            return `https://vidsrc-embed.ru/embed/tv/${media.id}/${season}/${episode}?autoplay=1&episodeselector=true&color-D81F26`
        }
        return `https://vidsrc-embed.ru/embed/${mediaType}/${media.id}?autoplay=1&color-D81F26`
    }
    
    useEffect(() => {
        const handleMessage = (event: MessageEvent) => {
            let data: any;
            try {
                data = typeof event.data === "string" ? JSON.parse(event.data) : event.data;
            } catch {

                return;
            }
            const type = data?.data.event;
            if (type === "pause") {
                document.body.classList.add("paused");
                // update episode and season if changed
                // logic only useful when using default episode selector from player
                // currently implemented a custom episode selector so this is useless
                if(data.data.mediaType === "tv") {
                    const episode = data.data.episode;
                    const season = data.data.season;
                    if(episode != searchParams.get("episode") || season != searchParams.get("season")) {
                        searchParams.set("episode", episode);
                        searchParams.set("season", season);
                        setSearchParams(searchParams);
                    }
                }
            }

            if (type === "play") {
                document.body.classList.remove("paused");
            }
        };

        window.addEventListener("message", handleMessage);
        return () => window.removeEventListener("message", handleMessage);
    }, []);

    useEffect(() => {
        if(mediaType === "tv") {
            const episode = searchParams.get("episode");
            const season = searchParams.get("season");
            // set(media.id.toString(), {season, episode});
            upsertShowHistory("show-history", {
                showId: media.id,
                season,
                episode,
                updatedAt: new Date()
            })
        }
    }, [searchParams, mediaType, media])

    return (
        <AppPlayer 
            cancelPlay={cancelPlay}
            modal={modal}
            src={getMediaSrc()}
        >
            <YouAreWatching />
            {mediaType === "tv" && <EpisodeSelector />}
        </AppPlayer>
    )
}