IF OBJECT_ID('DBO.Abone_Tarife_Fatura_Islemleri') IS NOT NULL
BEGIN
	DROP PROCEDURE Abone_Tarife_Fatura_Islemleri
END

GO

-- Bu prosed�r, aboneye ait tarife bilgilerini g�nceller, yeni bir tarife atar ve ili�kili fatura i�lemlerini ger�ekle�tirir.
CREATE PROCEDURE Abone_Tarife_Fatura_Islemleri
    @TCKimlikNo CHAR(11),
    @YeniTarifeIsim NVARCHAR(50),
    @SmsMiktari INT,
    @BasvuruYasi INT,
    @InternetMiktari INT,
    @KonusmaMiktari INT,
    @YeniAbonelerIcinYillik DECIMAL(10, 2),
    @YeniAbonelerIcinAylik DECIMAL(10, 2),
    @EskiAbonelerIcinYillik DECIMAL(10, 2),
    @EskiAbonelerIcinAylik DECIMAL(10, 2),
    @FaturaTutari DECIMAL(10, 2),
    @FaturaKesimTarihi DATE,
    @SonOdemeTarihi DATE
AS
BEGIN
    BEGIN TRANSACTION;

    BEGIN TRY
        IF NOT EXISTS (SELECT 1 FROM ABONE WHERE TC_KIMLIK_NO = @TCKimlikNo)
        BEGIN
            THROW 50001, 'Ge�ersiz TCKimlikNo: Abone bulunamad�.', 1;
        END

        -- Abonenin s�zle�mesini bul
        DECLARE @SozlesmeNumarasi INT;
        SELECT TOP 1 @SozlesmeNumarasi = SOZLESME_NUMARASI
        FROM ABONELIK_SOZLESMESI
        WHERE TC_KIMLIK_NO = @TCKimlikNo
        ORDER BY BITIS_TARIHI DESC ;

        IF @SozlesmeNumarasi IS NULL
        BEGIN
            THROW 50002, 'Abonelik s�zle�mesi bulunamad�.', 1;
        END

        -- �li�kili kay�tlar� kontrol et
        IF EXISTS (SELECT 1 FROM SOZLESME_PAKETI WHERE TARIFE_ID IN (SELECT TARIFE_ID FROM TARIFELER WHERE SOZLESME_NUMARASI = @SozlesmeNumarasi))
        BEGIN
            -- �li�kili kay�tlar� g�ncelle
            UPDATE SOZLESME_PAKETI
            SET TARIFE_ID = NULL
            WHERE TARIFE_ID IN (SELECT TARIFE_ID FROM TARIFELER WHERE SOZLESME_NUMARASI = @SozlesmeNumarasi);
        END

        -- Mevcut tarifeyi sil
        DELETE FROM TARIFELER WHERE SOZLESME_NUMARASI = @SozlesmeNumarasi;

        -- Yeni tarife ekle
        INSERT INTO TARIFELER (
            ISIM, 
            SMS_MIKTARI, 
            BASVURU_YASI, 
            INTERNET_MIKTARI, 
            KONUSMA_MIKTARI, 
            YENI_ABONELER_ICIN_YILLIK, 
            YENI_ABONELER_ICIN_AYLIK, 
            ESKI_ABONELER_ICIN_YILLIK, 
            ESKI_ABONELER_ICIN_AYLIK, 
            ILK_TARIH, 
            SON_TARIH, 
            ACIKLAMA, 
            SOZLESME_NUMARASI, 
            BASVURU_ID, 
            BASVURU_SEKLI_ID
        )
        VALUES (
            @YeniTarifeIsim,
            @SmsMiktari,
            @BasvuruYasi,
            @InternetMiktari,
            @KonusmaMiktari,
            @YeniAbonelerIcinYillik,
            @YeniAbonelerIcinAylik,
            @EskiAbonelerIcinYillik,
            @EskiAbonelerIcinAylik,
            GETDATE(),
            DATEADD(YEAR, 1, GETDATE()),
            'Yeni tarife atand�.',
            @SozlesmeNumarasi,
            NULL, -- Ba�vuru_ID varsay�lan NULL
            NULL  -- Ba�vuru_Sekli_ID varsay�lan NULL
        );

        PRINT 'Yeni tarife ba�ar�yla atand�.';

        -- Fatura bilgilerini g�ncelle veya ekle
        IF EXISTS (SELECT 1 FROM FATURA WHERE SOZLESME_NUMARASI = @SozlesmeNumarasi AND FATURA_KESIM_TARIHI = @FaturaKesimTarihi)
        BEGIN
            UPDATE FATURA
            SET FATURA_TUTARI = @FaturaTutari,
                SON_ODEME_BITIS_TARIHI = @SonOdemeTarihi
            WHERE SOZLESME_NUMARASI = @SozlesmeNumarasi AND FATURA_KESIM_TARIHI = @FaturaKesimTarihi;

            PRINT 'Mevcut fatura g�ncellendi.';
        END
        ELSE
        BEGIN
            INSERT INTO FATURA (FATURA_TUTARI, FATURA_KESIM_TARIHI, FATURA_BASLANGIC_TARIHI, FATURA_BITIS_TARIHI, SON_ODEME_BITIS_TARIHI, SOZLESME_NUMARASI)
            VALUES (
                @FaturaTutari,
                @FaturaKesimTarihi,
                GETDATE(),
                DATEADD(MONTH, 1, GETDATE()),
                @SonOdemeTarihi,
                @SozlesmeNumarasi
            );

            PRINT 'Yeni fatura olu�turuldu.';
        END

        COMMIT TRANSACTION;
        PRINT 'T�m i�lemler ba�ar�yla tamamland�.';
    END TRY
    BEGIN CATCH
        ROLLBACK TRANSACTION;
        DECLARE @ErrorMessage NVARCHAR(4000) = ERROR_MESSAGE();
        PRINT 'Hata meydana geldi: ' + @ErrorMessage;
    END CATCH
END;


--Abonenin Sistemde Oldu�u ve Ge�erli Bir S�zle�mesinin Bulundu�u Durum
--EXEC Abone_Tarife_Fatura_Islemleri 
--    @TCKimlikNo = '78901234567',
--    @YeniTarifeIsim = 'Yeni Tarife',
--    @SmsMiktari = 200,
--    @BasvuruYasi = 20,
--    @InternetMiktari = 1500,
--    @KonusmaMiktari = 700,
--    @YeniAbonelerIcinYillik = 1300.00,
--    @YeniAbonelerIcinAylik = 110.00,
--    @EskiAbonelerIcinYillik = 1100.00,
--    @EskiAbonelerIcinAylik = 95.00,
--    @FaturaTutari = 250.00,
--    @FaturaKesimTarihi = '2024-12-01',
--    @SonOdemeTarihi = '2024-12-15';


--Sistemde Abone Olmayan Bir TC Kimlik No ile Test
--EXEC Abone_Tarife_Fatura_Islemleri 
--    @TCKimlikNo = '99999999999',
--    @YeniTarifeIsim = 'Hatal� Tarife',
--    @SmsMiktari = 300,
--    @BasvuruYasi = 25,
--    @InternetMiktari = 2000,
--    @KonusmaMiktari = 800,
--    @YeniAbonelerIcinYillik = 1400.00,
--    @YeniAbonelerIcinAylik = 120.00,
--    @EskiAbonelerIcinYillik = 1200.00,
--    @EskiAbonelerIcinAylik = 100.00,
--    @FaturaTutari = 200.00,
--    @FaturaKesimTarihi = '2024-12-01',
--    @SonOdemeTarihi = '2024-12-15';


--S�zle�mesi Olmayan Bir Abone i�in Test
--EXEC Abone_Tarife_Fatura_Islemleri 
--    @TCKimlikNo = '10000000007',
--    @YeniTarifeIsim = 'Yeni Tarife',
--    @SmsMiktari = 300,
--    @BasvuruYasi = 25,
--    @InternetMiktari = 2000,
--    @KonusmaMiktari = 800,
--    @YeniAbonelerIcinYillik = 1400.00,
--    @YeniAbonelerIcinAylik = 120.00,
--    @EskiAbonelerIcinYillik = 1200.00,
--    @EskiAbonelerIcinAylik = 100.00,
--    @FaturaTutari = 200.00,
--    @FaturaKesimTarihi = '2024-12-01',
--    @SonOdemeTarihi = '2024-12-15';


--Mevcut Faturan�n G�ncellenmesi Durumu
--EXEC Abone_Tarife_Fatura_Islemleri 
--    @TCKimlikNo = '78901234567',
--    @YeniTarifeIsim = 'G�ncellenmi� Tarife',
--    @SmsMiktari = 300,
--    @BasvuruYasi = 25,
--    @InternetMiktari = 2000,
--    @KonusmaMiktari = 800,
--    @YeniAbonelerIcinYillik = 1400.00,
--    @YeniAbonelerIcinAylik = 120.00,
--    @EskiAbonelerIcinYillik = 1200.00,
--    @EskiAbonelerIcinAylik = 100.00,
--    @FaturaTutari = 200.00,
--    @FaturaKesimTarihi = '2024-12-01',
--    @SonOdemeTarihi = '2024-12-20';

	--SELECT * FROM TARIFELER
	--SELECT * FROM FATURA WHERE SOZLESME_NUMARASI = 51 AND FATURA_KESIM_TARIHI = '2024-12-01';


	--SELECT * FROM ABONELIK_SOZLESMESI
	--SELECT * FROM FATURA
	--SELECT * FROM ABONE
	--SELECT * FROM TARIFELER
