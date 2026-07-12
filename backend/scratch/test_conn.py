import asyncio
from sqlalchemy.ext.asyncio import create_async_engine

async def main():
    uri = "postgresql+asyncpg://postgres.knynttctxndoslqbajyp:civicvoice%4012@aws-1-ap-south-1.pooler.supabase.com:5432/postgres"
    print(f"Testing connection to: {uri}")
    try:
        engine = create_async_engine(uri)
        async with engine.connect() as conn:
            result = await conn.execute("SELECT 1")
            val = result.scalar()
            print(f"Connection SUCCESS! Select 1 returned: {val}")
    except Exception as e:
        print(f"Connection FAILED: {e}")

if __name__ == "__main__":
    asyncio.run(main())
