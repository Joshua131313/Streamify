import { FaLongArrowAltLeft, FaExpand, FaCompress } from "react-icons/fa";
import { Icon } from "../Icon/Icon";
import { createPortal } from "react-dom";
import React, { useEffect, useRef, useState } from "react";
import "./AppPlayer.css";
import { useApp } from "../../../context/AppContext";

interface Props {
    modal?: boolean;
    children?: React.ReactNode;
    controls?: React.ReactNode;
    cancelPlay?: () => void;
    src: string;
    className?: string;
}

export const AppPlayer = React.memo((props: Props) => {
    const { modal = true, children, cancelPlay, src, className } = props;
    const { isMobile } = useApp();
    const iframeRef = useRef<HTMLIFrameElement>(null);
    const wrapperRef = useRef<HTMLDivElement>(null);

    const [isFullscreen, setIsFullscreen] = useState(false);

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

    const toggleFullscreen = async () => {
        if (!wrapperRef.current) return;

        if (!document.fullscreenElement) {
            await wrapperRef.current.requestFullscreen();
        } else {
            await document.exitFullscreen();
        }
    };

    useEffect(() => {
        const handleChange = () => {
            setIsFullscreen(!!document.fullscreenElement);
        };

        document.addEventListener("fullscreenchange", handleChange);
        return () => {
            document.removeEventListener("fullscreenchange", handleChange);
        };
    }, []);

    const content = (
        <div
            ref={wrapperRef}
            className={`player ${modal ? "modal-player" : ""} ${className}`}
        >
            {modal && (
                <Icon
                    className="back-icon player-control-icon"
                    Icon={FaLongArrowAltLeft}
                    onClick={cancelPlay}
                />
            )}

            {
                !isMobile &&
                <Icon
                    className="fullscreen-icon player-control-icon"
                    Icon={isFullscreen ? FaCompress : FaExpand}
                    onClick={toggleFullscreen}
                />
            }

            {children}

            <div className="iframe">
                <div className="iframe-intercept"></div>
                <iframe
                    ref={iframeRef}
                    allow="encrypted-media; autoplay; fullscreen"
                    src={src}
                ></iframe>

                {props.controls}
            </div>
        </div>
    );

    return modal
        ? createPortal(content, document.body)
        : content;
});