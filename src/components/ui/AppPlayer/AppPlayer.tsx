import { FaLongArrowAltLeft } from "react-icons/fa"
import { Icon } from "../Icon/Icon"
import { createPortal } from "react-dom"
import React, { useEffect, useRef } from "react"
import "./AppPlayer.css"

interface Props {
    modal?: boolean;
    children?: React.ReactNode;
    cancelPlay: () => void;
    src: string;
    className?: string;
}
export const AppPlayer = React.memo((props: Props) => {
    const { modal = true, children, cancelPlay, src, className } = props;

    const iframeRef = useRef<HTMLIFrameElement>(null);

    useEffect(() => {
        if (iframeRef.current && iframeRef.current.src !== src) {
            iframeRef.current.src = src;
        }
    }, [src]);

    useEffect(() => {
        if (modal) {
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

    const Player = () => {
        return (
            <div className={`player ${modal ? "modal-player" : ""} ${className}`}>
                {modal && (
                    <Icon
                        className="back-icon player-control-icon"
                        Icon={FaLongArrowAltLeft}
                        onClick={cancelPlay}
                    />
                )}

                {children}

                <iframe src={src} ref={iframeRef} allowFullScreen allow="encrypted-media; autoplay; fullscreen"/>
            </div>
        );
    };

    return modal
        ? createPortal(<Player />, document.body)
        : <Player />;
});