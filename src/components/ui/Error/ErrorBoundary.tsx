import React, { Component } from "react";
import "./ErrorBoundary.css"
import { Container } from "../../layout/Container/Container";
import { Button } from "../Button/Button";
import { StaticLogo } from "../Logo/StaticLogo";

type Props = {
  children: React.ReactNode;
  fallback?: React.ReactNode;
};

type State = {
  hasError: boolean;
  error: Error | null;
};

export class ErrorBoundary extends Component<Props, State> {
  constructor(props: Props) {
    super(props);
    this.state = {
      hasError: false,
      error: null,
    };
  }

  static getDerivedStateFromError(error: Error): State {
    return {
      hasError: true,
      error,
    };
  }

  componentDidCatch(error: Error, errorInfo: React.ErrorInfo) {
    console.error("ErrorBoundary caught:", error, errorInfo);

    // 🔥 optional: send to logging service
    // logError(error, errorInfo);
  }

  handleReset = () => {
    this.setState({ hasError: false, error: null });
  };

  render() {
    if (this.state.hasError) {
      // custom fallback if provided
      if (this.props.fallback) {
        return this.props.fallback;
      }

      return (
            <Container className="error-content">
               <StaticLogo />
                <h2>Something went wrong...</h2>
                <a href="/">
                  <Button>Return Home</Button>
                 </a>
            </Container>
      );
    }

    return this.props.children;
  }
}