"use client";

import * as React from "react";
import { useWallet } from "@privy-io/react-auth";
import { useMiniPayDetection } from "@/lib/minipay";
import { celoMainnet, celoSepolia, chainById, SupportedChainId } from "@/lib/chain";

interface WalletButtonProps {
  className?: string;
}

export function WalletButton({ className }: WalletButtonProps = {}) {
  const { wallet, prepare, connect, disconnect: privyDisconnect } = useWallet();
  const isMiniPay = useMiniPayDetection();
  const [account, setAccount] = React.useState<string | null>(null);
  const [chainId, setChainId] = React.useState<number | null>(null);
  const [anchorEl, setAnchorEl] = React.useState<null | HTMLElement>(null);
  const [isLongPress, setIsLongPress] = React.useState(false);
  const open = Boolean(anchorEl);

  // MiniPay detection: if MiniPay is detected, we try to get accounts and chainId from window.ethereum
  React.useEffect(() => {
    if (isMiniPay) {
      if (typeof window !== "undefined" && window.ethereum) {
        window.ethereum
          .request({ method: "eth_requestAccounts" })
          .then((accounts: string[]) => {
            if (accounts.length > 0) {
              setAccount(accounts[0]);
              return window.ethereum.request({ method: "eth_chainId" });
            }
            setAccount(null);
            setChainId(null);
          })
          .then((chainIdHex: string) => {
            setChainId(parseInt(chainIdHex, 16));
          })
          .catch(() => {
            setAccount(null);
            setChainId(null);
          });
      }
    } else {
      // When not MiniPay, we rely on Privy's wallet state
      setAccount(wallet?.address ?? null);
      setChainId(wallet?.chainId ?? null);
    }
  }, [isMiniPay, wallet]);

  const handleDisconnect = () => {
    setAnchorEl(null);
    if (isMiniPay) {
      // For MiniPay, we just clear local state
      setAccount(null);
      setChainId(null);
    } else {
      privyDisconnect();
    }
  };

  const handleContextMenu = (e: React.MouseEvent) => {
    e.preventDefault(); // Prevent default context menu
    setAnchorEl(e.currentTarget as HTMLElement);
  };

  const handleClick = (e: React.MouseEvent) => {
    // If right-click, we already handled in contextMenu
    if (e.button === 2) return;
    // For MiniPay, we don't need to do anything on click (already connected)
    // For Privy, we want to open the modal to connect if not connected
    if (!isMiniPay && !wallet?.address) {
      connect();
    }
  };

  // Touch events for long-press on mobile
  const handleTouchStart = (e: React.TouchEvent) => {
    setIsLongPress(false);
    setTimeout(() => {
      setIsLongPress(true);
    }, 500); // 500ms for long-press
  };

  const handleTouchEnd = (e: React.TouchEvent) => {
    if (isLongPress) {
      e.preventDefault();
      handleDisconnect();
    }
    setIsLongPress(false);
  };

  // Render context menu (simple disconnect option)
  const contextMenu = (
    <div className="absolute right-0 mt-2 w-56 origin-top-right rounded-md bg-popover p-1 shadow-lg border border-border z-50 focus:outline-none">
      <div
        className="flex items-center p-2 text-sm text-foreground hover:bg-accent hover:text-accent-foreground rounded-md"
        onClick={handleDisconnect}
      >
        Disconnect
      </div>
    </div>
  );

  // Determine display content
  let content: React.ReactNode;
  if (isMiniPay && account) {
    const truncated = `${account.slice(0, 4)}...${account.slice(-4)}`;
    const chain = chainById(chainId as SupportedChainId);
    const chainName = chain ? chain.name : "Unknown";
    content = (
      <>
        {truncated}
        <span className="ml-2 inline-flex h-6 w-6 items-center justify-center rounded-md text-xs font-medium">
          {chainName}
        </span>
      </>
    );
  } else if (!isMiniPay && wallet?.address) {
    const truncated = `${wallet.address.slice(0, 4)}...${wallet.address.slice(-4)}`;
    const chain = chainById(wallet.chainId as SupportedChainId);
    const chainName = chain ? chain.name : "Unknown";
    content = (
      <>
        {truncated}
        <span className="ml-2 inline-flex h-6 w-6 items-center justify-center rounded-md text-xs font-medium">
          {chainName}
        </span>
      </>
    );
  } else {
    content = <span>Connect Wallet</span>;
  }

  return (
    <button
      className={`
        flex items-center gap-2 px-3 py-2 rounded-md text-sm font-medium
        hover:bg-accent hover:text-accent-foreground focus:outline-none focus:ring-2 focus:ring-ring focus:ring-offset-2
        disabled:pointer-events-none disabled:opacity-50
        ${className ?? ""}
     `}
      onClick={handleClick}
      onContextMenu={handleContextMenu}
      onTouchStart={handleTouchStart}
      onTouchEnd={handleTouchEnd}
    >
      {content}
      {open && contextMenu}
    </button>
  );
}
