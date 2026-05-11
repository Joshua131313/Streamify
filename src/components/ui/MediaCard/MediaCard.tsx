import "./MediaCard.css";

import {
    useEffect,
    useMemo,
    useRef,
    useState
} from "react";

import {
    Link
} from "react-router-dom";

import YouTube, {
    type YouTubeEvent,
    type YouTubePlayer,
    type YouTubeProps
} from "react-youtube";

import {
    FaStar,
    FaVolumeMute,
    FaVolumeUp
} from "react-icons/fa";

import type {
    TMDBMedia
} from "../../../types/TMDBMediaType";

import { TMDBImg }
from "../ImgProxy/TMDBImg";

import { useApp }
from "../../../context/AppContext";

import { MediaCardInfo }
from "./MediaCardInfo";

import { getOfficialYoutubeTrailerId }
from "../../../utils/helpers";

import { useTMDBQuery }
from "../../../hooks/mediaHooks/tmdbHooks/useTMDBQuery";
import { Icon } from "../Icon/Icon";
import { SaveMediaButton } from "../Button/SaveMediaButton";

interface Props {
    media: TMDBMedia;
    className?: string;
}

type TMDBVideosResponse = {
    results: {
        key: string;
        site: string;
        type: string;
        official: boolean;
    }[];
};

export const MediaCard = (props: Props) => {

    const { media, className } = props;

    const { isMobile } = useApp();

    const [hovered, setHovered] =
        useState(false);

    const [loadTrailer, setLoadTrailer] =
        useState(false);

    const [showTrailer, setShowTrailer] =
        useState(false);

    const [muted, setMuted] =
        useState(true);

    const playerRef =
        useRef<YouTubePlayer | null>(null);

    useEffect(() => {

        if (!hovered) {

            setLoadTrailer(false);

            setShowTrailer(false);

            return;
        }

        const preloadTimer =
            setTimeout(() => {
                setLoadTrailer(true);
            }, 1000);

        const showTimer =
            setTimeout(() => {
                setShowTrailer(true);
            }, 2000);

        return () => {

            clearTimeout(preloadTimer);

            clearTimeout(showTimer);
        };

    }, [hovered]);

    const {
        data: videos
    } = useTMDBQuery<TMDBVideosResponse>({
        endpoint:
            `/${media.mediaType}/${media.id}/videos`,

        enabled:
            loadTrailer &&
            !isMobile
    });

    const trailerId = useMemo(() => {

        return getOfficialYoutubeTrailerId(
            videos?.results ?? []
        );

    }, [videos]);

    const opts: YouTubeProps["opts"] =
        useMemo(() => ({
            width: "100%",
            height: "100%",

            playerVars: {
                autoplay: 1,
                mute: 1,

                controls: 0,
                disablekb: 1,
                fs: 0,

                modestbranding: 1,
                rel: 0,

                iv_load_policy: 3,
                cc_load_policy: 0,

                playsinline: 1,

                loop: 1,
                playlist: trailerId,

                origin: window.location.origin,
            },
        }), [trailerId]);

    const handleReady =
        (event: YouTubeEvent) => {

            playerRef.current =
                event.target;

            event.target.mute();

            event.target.playVideo();
        };

    const toggleMute =
        (e: React.MouseEvent) => {

            e.preventDefault();

            e.stopPropagation();

            if (!playerRef.current) {
                return;
            }

            if (muted) {

                playerRef.current.unMute();

            } else {

                playerRef.current.mute();
            }

            setMuted(!muted);
        };

    return (
        <>
            {
                isMobile ?

                    <Link
                        to={`/${media.mediaType}/${media.id}`}
                        className={`mobile-media-card ${className}`}
                    >

                        <TMDBImg
                            type="poster"
                            size="w342"
                            path={media.poster_path ?? ""}
                        />
                        <MediaCardInfo media={media} />
                    </Link>

                    :

                    <div
                        className={`media-card ${className}`}

                        onMouseEnter={() => {
                            setHovered(true);
                        }}

                        onMouseLeave={() => {
                            setHovered(false);
                        }}
                    >

                        <Link
                            to={`/${media.mediaType}/${media.id}`}
                            className="media-card-content"
                        >

                            {
                                showTrailer && trailerId ?

                                    <>
                                        <YouTube
                                            videoId={trailerId}
                                            className={`
                                                yt-iframe
                                                ${showTrailer ? "visible" : "hidden"}
                                            `}
                                            opts={opts}
                                            onReady={handleReady}
                                        />

                                        {
                                            showTrailer && (
                                                <>
                                                    <SaveMediaButton media={media} />
                                                    <Icon className="mute-icon" Icon={muted ? FaVolumeMute : FaVolumeUp} onClick={(e) => toggleMute(e)}/>
                                                </>
                                            )
                                        }
                                    </>

                                    :

                                    <TMDBImg
                                        type="backdrop"
                                        size="w780"
                                        path={media.backdrop_path ?? ""}
                                    />
                            }

                            <div className="media-card-overlay"></div>

                            <div className="media-info flex-col">

                                <span className="media-title">
                                    {media.title}
                                </span>

                                <div className="flex-row sb">

                                    <small>
                                        {
                                            media.mediaType === "movie"
                                                ? "Movie"
                                                : "Series"
                                        }
                                    </small>

                                    <div className="flex-row media-rating">

                                        <FaStar className="text-red-500" />

                                        <small className="rating">
                                            {media.vote_average}/10
                                        </small>

                                    </div>

                                </div>

                            </div>

                        </Link>

                        <MediaCardInfo media={media} />

                    </div>
            }
        </>
    );
};