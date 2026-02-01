import type { YouTubeProps } from "react-youtube";
import "./Trailer.css"
import YouTube from "react-youtube";
import { useRef, useState } from "react";
import { TMDBImg } from "../TMDBImg/TMDBImg";
import {  FaDownload, FaLongArrowAltLeft, FaPlus, FaVolumeMute } from "react-icons/fa";
import { Icon } from "../Icon/Icon";
import { FaVolumeHigh } from "react-icons/fa6";
import { useNavigate } from "react-router-dom";
import { MediaMetaBadges, type MediaMetaBadgesProps } from "../MediaMetaBadges/MediaMetaBadges";
import { PlayButton } from "../Button/PlayButton";
import type { TMediaType } from "../../../types/genericTypes";
import { Button } from "../Button/Button";

interface Props {
    backdrop_path: string;
    logo_path: string;
    trailer_id: string;
    mediaMetaBadgesProps: MediaMetaBadgesProps;
    description: string;
    mediaId: number;
    mediaType: TMediaType;
}

export const Trailer = (props : Props) => {
    const { backdrop_path, trailer_id, logo_path, mediaMetaBadgesProps, description, mediaId, mediaType } = props;
    const [playing, setPlaying] = useState(false);
    const [muted, setMuted] = useState(true);
    const playerRef = useRef<any>(null);
    const trailerContainerRef = useRef<HTMLDivElement>(null);
    const navigate = useNavigate();

    const opts: YouTubeProps["opts"] = {
        width: "100%",
        height: "100%",
        playerVars: {
        autoplay: 1,
        mute: 1,
        controls: 0,
        rel: 0,
        modestbranding: 1,
        disablekb: 1,
        playsinline: 1,
        loop: 1,
        playlist: trailer_id, 
        },
    };

    const onReady: YouTubeProps["onReady"] = (e) => {
        playerRef.current = e.target;
    }

    const onEnd: YouTubeProps["onEnd"] = (e) => {
        e.target.playVideo(); // 🔁 restart when finished (extra safety)
    };

    const onStateChange: YouTubeProps["onStateChange"] = (e) => {
        if(e.data === 1) {
            setPlaying(true)
        }
    }

    const toggleMute = () => {
        if(!playerRef.current) return;

        if(muted) {
            playerRef.current.unMute();
            playerRef.current.setVolume(100);
        }
        else {
            playerRef.current.mute();
        }
        setMuted(!muted)
    }
    const handleMouseMove = (e : React.MouseEvent<HTMLDivElement>) => {
        const el = e.currentTarget;
        const hovered = el.classList.contains("trailer-hovered");
        if(!hovered) {
            el.classList.add("trailer-hovered")
        }
    }
    const handleMouseOver = (e : React.MouseEvent<HTMLDivElement>) => {
       console.log('over')
        e.currentTarget.classList.add("trailer-hovered")
    }
    const handleMouseLeave = (e : React.MouseEvent<HTMLDivElement>) => {
        const el = e.currentTarget;
        setTimeout(()=> {
            el.classList.remove("trailer-hovered");
        }, 5000)
    }


    return (
       <div ref={trailerContainerRef} className={`trailer trailer-hovered`}onMouseMove={handleMouseMove} onMouseOver={handleMouseOver} onMouseLeave={handleMouseLeave}>
        <div className="trailer-controls">
            <Icon 
                Icon={FaLongArrowAltLeft}
                onClick={() => navigate("/")}
            />
            <Icon
                onClick={()=> toggleMute()} 
                Icon={muted ? FaVolumeMute : FaVolumeHigh} 
            />
        </div>
        <div className="trailer-info">
            <div className="inner-trailer-info">
                <TMDBImg path={logo_path} />
                <MediaMetaBadges 
                    {...mediaMetaBadgesProps}
                />
                <div className="description">
                    {description}
                </div>
                <div className="trailer-action-buttons flex">
                    <PlayButton mediaId={mediaId} mediaType={mediaType}/>
                    <Icon Icon={FaPlus}/>
                    {
                        mediaType === "movie" ? 
                        <Icon Icon={FaDownload}/> 
                        : 
                        <Button className="secondary">Episodes</Button>
                    }
                    <Button className="secondary">Similars</Button>
                </div>
            </div>
        </div>
        <TMDBImg 
            path={backdrop_path} 
            className={`trailer-backdrop ${playing ? "fade-out" : ""}`}
        />
        <YouTube
            videoId={trailer_id}
            opts={opts}
            onEnd={onEnd}
            className="yt-iframe"
            onStateChange={onStateChange}
            onReady={onReady}
        />
        <div className="hero-overlay"></div>

       </div>
    )
}