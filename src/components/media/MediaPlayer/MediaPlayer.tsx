import { FaLongArrowAltLeft } from "react-icons/fa"
import { Icon } from "../../ui/Icon/Icon"
import { createPortal } from "react-dom"
import { useSearchParams } from "react-router-dom"
import { useEffect } from "react"
import "./MediaPlayer.css"
import { YouAreWatching } from "./YouAreWatching"
import { useMediaLayoutContext } from "../../layout/MediaLayout/MediaLayoutContext"

export const MediaPlayer = ({ modal = true} : { modal?: boolean}) => {
    const [searchParams, setSearchParams] = useSearchParams();
    const { media, mediaType } = useMediaLayoutContext();

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
        if(modal) {
            document.body.classList.add("player-open");
            const scrollY = window.scrollY;
            document.body.style.position = "fixed";
            document.body.style.top = `-${scrollY}px`;
            document.body.style.width = "100%";
            return () => {
                const scrollY = document.body.style.top;
                document.body.style.position = "";
                document.body.style.top = "";
                document.body.style.width = "";
                window.scrollTo(0, parseInt(scrollY || "0") * -1);
                document.body.classList.remove("player-open");
            };
        }
    }, [modal]);

    useEffect(() => {
        const allowedOrigins = [
            "https://www.vidking.cc",
            "https://www.vidking.to",
            "https://www.vidking.pro",
            "https://www.vidking.net",
            "https://vidsrc-embed.ru"
        ];

        const handleMessage = (event: MessageEvent) => {
            if (!allowedOrigins.includes(event.origin)) return;
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



    const Player = () => {
        return (
            <div className={`player ${modal ? "modal-player" : ""}`} role="dialog" aria-modal="true">
                {modal && <Icon Icon={FaLongArrowAltLeft} onClick={cancelPlay}/>}
                <YouAreWatching />
                <iframe 
                    src={getMediaSrc()} 
                    allowFullScreen
                />
            </div>
        )
    }

    return (
        modal ?
        createPortal(
            <Player />
        , document.body
        )
        : <Player />
    )
}