export const dynamic = "force-dynamic";

export async function POST(
  request: Request
) {
  const rpcUrl =
    process.env.SEPOLIA_RPC_URL;

  if (!rpcUrl) {
    return Response.json(
      {
        error:
          "SEPOLIA_RPC_URL is not configured",
      },
      { status: 500 }
    );
  }

  const body =
    await request.text();

  const response =
    await fetch(rpcUrl, {
      method: "POST",
      headers: {
        "content-type":
          "application/json",
      },
      body,
      cache: "no-store",
    });

  const result =
    await response.text();

  return new Response(result, {
    status: response.status,
    headers: {
      "content-type":
        "application/json",
    },
  });
}
