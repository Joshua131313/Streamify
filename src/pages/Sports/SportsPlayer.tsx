import { useSearchParams } from "react-router-dom";
import {
    formatChannel,
    getSportStream,
    getStreamURL
} from "../../utils/sports/sportsUtils";
import { AppPlayer } from "../../components/ui/AppPlayer/AppPlayer";
import type { Leagues, TStreamProvider, GameProps } from "../../types/sports/sportsTypes";
import { Icon } from "../../components/ui/Icon/Icon";
import { FaChevronDown, FaChevronUp } from "react-icons/fa";
import { Input } from "../../components/ui/Input/Input";
import { useState, useEffect } from "react";
import { Button } from "../../components/ui/Button/Button";
import { useSports } from "../../context/SportsContext";

export const SportsPlayer = () => {
    const [searchParams, setSearchParams] = useSearchParams();
    const { getGameById } = useSports();

    // 🔹 Params
    const provider = searchParams.get("provider");
    const channel = searchParams.get("channel");
    const gameId = searchParams.get("gameId");
    const league = searchParams.get("league") as Leagues | null;

    const isTV = searchParams.get("tv") === "1";

    // 🔹 Streams
    const allStreams = league ? getSportStream(league) : [];

    // 🔹 TV input state
    const [inputValue, setInputValue] = useState(channel || "");
    const channelAsNumber = Number(channel);
    const decrementChannelButtonEnabled = channelAsNumber > 1;

    useEffect(() => {
        if (channel !== inputValue) {
            setInputValue(channel || "");
        }
    }, [channel]);

    // 🔥 Freeze game
    const [stableGame, setStableGame] = useState<GameProps | null>(null);

    useEffect(() => {
        setStableGame(null);
    }, [gameId]);

    useEffect(() => {
        if (!stableGame && league && gameId) {
            const g = getGameById(league, gameId);
            console.log(g)
            if (g) setStableGame(g);
        }
    }, [league, gameId, stableGame, getGameById]);

    // 🔥 Channel update
    const updateChannel = (newChannel: string) => {
        if (!newChannel || isNaN(Number(newChannel))) return;

        const formatted = formatChannel(newChannel, provider!);

        if (formatted === channel) return;

        const newParams = new URLSearchParams(searchParams);
        newParams.set("channel", formatted);
        setSearchParams(newParams);
    };

    const incrementChannel = () => {
        updateChannel(String(channelAsNumber + 1));
    };

    const decrementChannel = () => {
        if (decrementChannelButtonEnabled) {
            updateChannel(String(channelAsNumber - 1));
        }
    };

    // 🔁 Provider switch
    const switchProvider = (newProvider: TStreamProvider) => {
        const newParams = new URLSearchParams(searchParams);
        newParams.set("provider", newProvider);
        setSearchParams(newParams);
    };

    // ❌ Cancel player
    const cancelWatch = () => {
        const newParams = new URLSearchParams(searchParams);
        newParams.delete("provider");
        newParams.delete("channel");
        newParams.delete("gameId");
        newParams.delete("league");
        newParams.delete("tv");
        setSearchParams(newParams, { replace: true });
    };

    // 🔥 FINAL SOURCE STATE (KEY FIX)
    const [playerSrc, setPlayerSrc] = useState<string | null>(null);

    useEffect(() => {
        let newSrc: string | null = null;

        if (isTV) {
            if (provider && channel) {
                newSrc = getStreamURL(provider as TStreamProvider, channel);
            }
        } else {
            if (provider && stableGame && league) {
                const stream = allStreams.find(s => s.provider === provider);
                if (stream) {
                    newSrc = stream.buildStreamUrl(stableGame);
                }
            }
        }

        // ✅ update only when needed
        if (newSrc && newSrc !== playerSrc) {
            setPlayerSrc(newSrc);
        }

        // ✅ clear player when params gone
        if (!newSrc) {
            setPlayerSrc(null);
        }

    }, [isTV, provider, channel, stableGame, league]);

    // ❌ No player → remove completely
    if (!playerSrc) return null;

    return (
        <>
            {/* 🔁 Provider switch */}
            {allStreams.length > 0 && (
                <div className="alt-streams">
                    {allStreams.map(stream => (
                        <Button
                            key={stream.provider}
                            onClick={() => switchProvider(stream.provider)}
                        >
                            {stream.provider}
                        </Button>
                    ))}
                </div>
            )}

            {/* 🎥 Player */}
            <AppPlayer
                cancelPlay={cancelWatch}
                src={playerSrc}
            />

            {/* 📺 TV Controls */}
            {isTV && (
                <div className="stream-controls">
                    <Icon Icon={FaChevronUp} onClick={incrementChannel} />

                    <Input
                        value={inputValue}
                        onChange={(e) => {
                            const val = e.target.value;
                            if (/^\d*$/.test(val)) {
                                setInputValue(val);
                            }
                        }}
                        onBlur={() => updateChannel(inputValue)}
                        onKeyDown={(e) => {
                            if (e.key === "Enter") {
                                updateChannel(inputValue);
                            }
                        }}
                    />

                    <Icon Icon={FaChevronDown} onClick={decrementChannel} />
                </div>
            )}
        </>
    );
};