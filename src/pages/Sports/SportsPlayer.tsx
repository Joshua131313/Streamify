import { useSearchParams } from "react-router-dom";
import { formatChannel, getStreamURL } from "../../utils/sports/sportsUtils";
import { AppPlayer } from "../../components/ui/AppPlayer/AppPlayer";
import type { TStreamProvider } from "../../types/sports/sportsTypes";
import { Icon } from "../../components/ui/Icon/Icon";
import { FaChevronDown, FaChevronUp } from "react-icons/fa";
import { Input } from "../../components/ui/Input/Input";
import { useState, useEffect } from "react";

export const SportsPlayer = () => {
    const [searchParams, setSearchParams] = useSearchParams();

    const provider = searchParams.get("provider");
    const channel = searchParams.get("channel");

    const [inputValue, setInputValue] = useState(channel || "");

    const channelAsNumber = Number(channel);
    const isTVChannels = searchParams.get("tv") === "1";
    const decrementChannelButtonEnabled = channelAsNumber > 1;

    // ✅ keep input in sync ONLY when URL changes externally


    const updateChannel = (newChannel: string) => {
        if (!newChannel || isNaN(Number(newChannel))) return;

        const formattedChannel = formatChannel(newChannel, provider!);

        if (formattedChannel === channel) return;

        const newParams = new URLSearchParams(searchParams);
        newParams.set("channel", formattedChannel);
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

    const cancelWatch = () => {
        const newParams = new URLSearchParams(searchParams);
        newParams.delete("provider");
        newParams.delete("channel");
        newParams.delete("tv");
        setSearchParams(newParams, { replace: true });
    };
    useEffect(() => {
        setInputValue(channel || "");
    }, [channel]);

    return (
        channel && provider ? (
            <>
                <AppPlayer
                    cancelPlay={cancelWatch}
                    src={getStreamURL(provider as TStreamProvider, channel)}
                />

                {isTVChannels && (
                    <div className="channels-controls">
                        <Icon Icon={FaChevronUp} onClick={incrementChannel} />

                        <Input
                            value={inputValue}
                            onChange={(e) => setInputValue(e.target.value)}
                            onBlur={() => updateChannel(inputValue)} // update when done
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
        ) : null
    );
};