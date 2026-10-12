import { useSearchParams } from "react-router-dom";
import { useEffect, useRef, useCallback } from "react";
import "./MediaPlayer.css";

import { YouAreWatching } from "./YouAreWatching";
import { useMediaLayoutContext } from "../../layout/MediaLayout/MediaLayoutContext";
import { AppPlayer } from "../../ui/AppPlayer/AppPlayer";
import { EpisodeSelector } from "./EpisodeSelector";
import { useWatchHistoryContext } from "../../../context/WatchHistoryContext";
import { buildMediaEmbedUrl, getMediaServer, mediaServers } from "../../../data/mediaServers";
import { PlayerSelect } from "../../ui/PlayerSelect/PlayerSelect";

export const MediaPlayer = ({ modal = true }: { modal?: boolean }) => {
    const [searchParams, setSearchParams] = useSearchParams();

    const { media, mediaType } = useMediaLayoutContext();
    const server = getMediaServer(searchParams.get("server"));

    const switchServer = (id: string) => {
        const params = new URLSearchParams(searchParams);
        params.set("server", getMediaServer(id).id);
        setSearchParams(params, { replace: true });
    };

    const {
        saveHistory,
        removeHistory
    } = useWatchHistoryContext();

    const hasInitializedRef =
        useRef(false);

    const lastEpisodeRef =
        useRef<string | null>(null);

    const lastHistorySaveRef =
        useRef<number>(0);

    const seasonParam =
        searchParams.get("season");

    const episodeParam =
        searchParams.get("episode");

    const cancelPlay = () => {

        const newParams =
            new URLSearchParams(searchParams);

        updateHistory();

        newParams.delete("play");
        newParams.delete("season");
        newParams.delete("episode");
        newParams.delete("server");

        setSearchParams(newParams, {
            replace: true
        });
    };

    const getMediaSrc = () => {

        const season =
            Number(seasonParam) || 1;

        const episode =
            Number(episodeParam) || 1;

        return buildMediaEmbedUrl(server.id, mediaType === "tv" ? "tv" : "movie", media.id, season, episode);
    };

    const updateHistory = useCallback(async () => {

        const now =
            Date.now();

        // Prevent spam updates
        if (now - lastHistorySaveRef.current < 2000) {
            return;
        }

        lastHistorySaveRef.current = now;

        if (mediaType === "movie") {

            await saveHistory({
                mediaType: "movie",
                mediaId: media.id,
                genres: media.genres ?? [],
            });

            return;
        }

        const payload: {
            mediaType: "tv";
            genres: { id: number; name: string }[];
            mediaId: number;
            season?: number;
            episode?: number;
        } = {
            mediaType: "tv",
            mediaId: media.id,
            genres: media.genres ?? [],
        };

        if (seasonParam) {
            payload.season =
                Number(seasonParam);
        }

        if (episodeParam) {
            payload.episode =
                Number(episodeParam);
        }

        await saveHistory(payload);

    }, [
        media.id,
        media.genres,
        mediaType,
        seasonParam,
        episodeParam,
        saveHistory
    ]);

    useEffect(() => {

        const hasPlay =
            searchParams.has("play");

        if (!hasPlay) {
            return;
        }

        if (!hasInitializedRef.current) {

            hasInitializedRef.current = true;

            updateHistory();
        }

    }, [searchParams, updateHistory]);

    useEffect(() => {

        if (mediaType !== "tv") {
            return;
        }

        if (!seasonParam || !episodeParam) {
            return;
        }

        const key =
            `${seasonParam}-${episodeParam}`;

        // Prevent duplicate saves
        if (lastEpisodeRef.current === key) {
            return;
        }

        lastEpisodeRef.current = key;

        updateHistory();

    }, [
        mediaType,
        seasonParam,
        episodeParam,
        updateHistory
    ]);

    useEffect(() => {

        const handleMessage = (
            event: MessageEvent
        ) => {

            let data: any;

            try {

                data =
                    typeof event.data === "string"
                        ? JSON.parse(event.data)
                        : event.data;

            } catch {
                return;
            }

            const payload =
                data?.data;

            const type =
                payload?.event;

            if (!payload) {
                return;
            }

            if (type === "play") {

                document.body.classList.remove("paused");

                updateHistory();
            }

            if (type === "pause") {

                document.body.classList.add("paused");

                updateHistory();
            }

            if (type === "ended") {

                removeHistory(
                    media.id,
                    mediaType === "tv"
                        ? "tv"
                        : "movie"
                );
            }
        };

        window.addEventListener(
            "message",
            handleMessage
        );

        return () => {
            window.removeEventListener(
                "message",
                handleMessage
            );
        };

    }, [
        media.id,
        mediaType,
        updateHistory,
        removeHistory
    ]);

    return (
        <AppPlayer
            cancelPlay={cancelPlay}
            modal={modal}
            src={getMediaSrc()}
            className="media-player"
            controls={
                <div className="media-server-selector">
                    <PlayerSelect label="Streaming server" value={server.id} onChange={switchServer}
                        options={mediaServers.map(option => ({ value: option.id, label: option.label }))} />
                </div>
            }
        >
            <YouAreWatching />

            {mediaType === "tv" && (
                <EpisodeSelector />
            )}

        </AppPlayer>
    );
};
