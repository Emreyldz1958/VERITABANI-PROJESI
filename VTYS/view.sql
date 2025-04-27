IF OBJECT_ID('DBO.VmAboneBasvuruDetay') IS NOT NULL
BEGIN
	DROP VIEW VmAboneBasvuruDetay
END

GO

--Abonelerin temel bilgilerini (ad, soyad, TC, doðum tarihi, konum), en güncel fatura durumunu, baþvuru skorunu ve yaþ grubunu hesaplayarak bir görünümde toplar

CREATE VIEW VmAboneBasvuruDetay 
AS
SELECT 
    CONCAT(A.AD, ' ', A.SOYAD) AS AD_SOYAD,
    A.TC_KIMLIK_NO AS TC_NO,
    FORMAT(A.DOGUM_TARIHI, 'yyyy-MM-dd') AS DOGUM_TARIHI,
    CONCAT(I.AD, '-', ILCE.AD) AS KONUM,
    dbo.fncBasvuruSkoru(A.TC_KIMLIK_NO) AS BASVURU_SKORU,
    CASE 
        WHEN SF.ODENME_TARIHI IS NULL THEN 
            CONVERT(NVARCHAR(10), SF.FATURA_TUTARI) + ' TL ÖDENMEDÝ'
        ELSE 
            CONVERT(NVARCHAR(10), SF.FATURA_TUTARI) + ' TL ÖDENDÝ'
    END AS FATURA_DURUMU,
    CASE 
        WHEN SF.ODENME_TARIHI IS NULL THEN 
            CONVERT(NVARCHAR(50), FORMAT(SF.SON_ODEME_BITIS_TARIHI, 'yyyy-MM-dd')) + ' tarihine kadar ödenmelidir.'
        ELSE 
            CONVERT(NVARCHAR(50), FORMAT(SF.ODENME_TARIHI, 'yyyy-MM-dd')) + ' tarihinde ödendi.'
    END AS TARIH_BILGISI,
    CASE
        WHEN YEAR(GETDATE()) - YEAR(A.DOGUM_TARIHI) <= 30 THEN 'GENÇ'
        ELSE 'YETÝÞKÝN'
    END AS YAS_GRUBU
FROM ABONE A 
INNER JOIN ADRES AD ON A.TC_KIMLIK_NO = AD.TC_KIMLIK_NO
INNER JOIN IL I ON AD.IL_ID = I.IL_ID
INNER JOIN ILCE ON I.IL_ID = ILCE.IL_ID
INNER JOIN (
    SELECT 
        TC_KIMLIK_NO, 
        FATURA_ID, 
        FATURA_TUTARI, 
        SON_ODEME_BITIS_TARIHI, 
        ODENME_TARIHI,
        ROW_NUMBER() OVER (PARTITION BY TC_KIMLIK_NO ORDER BY SON_ODEME_BITIS_TARIHI DESC) AS RN
    FROM FATURA
) SF ON SF.TC_KIMLIK_NO = A.TC_KIMLIK_NO AND SF.RN = 1
GROUP BY 
    A.AD, A.SOYAD, A.TC_KIMLIK_NO, A.DOGUM_TARIHI, I.AD, ILCE.AD, dbo.fncBasvuruSkoru(A.TC_KIMLIK_NO), 
    SF.FATURA_TUTARI, SF.ODENME_TARIHI, SF.SON_ODEME_BITIS_TARIHI;



--SELECT * FROM TARIFELER
--SELECT * FROM VmAboneBasvuruDetay


--Genç yaþ grubundaki baþvurulara göre, yalnýzca 1 kontenjan saðlandýðý için, en yüksek baþvuru skoruna sahip kiþiye "Hak Kazandýnýz" mesajý, diðer baþvuru sahiplerine ise "Yetersiz Kontenjan" mesajý verilir; diðer yaþ gruplarý için "Þartlar Saðlanmadý" mesajý döndürülür.

SELECT V.AD_SOYAD, V.BASVURU_SKORU, V.FATURA_DURUMU, V.YAS_GRUBU,
CASE
    WHEN YAS_GRUBU = 'GENÇ' AND BASVURU_SKORU > 50 AND V.BASVURU_SKORU = (
        SELECT TOP 1 BASVURU_SKORU
        FROM VmAboneBasvuruDetay
        WHERE YAS_GRUBU = 'GENÇ' AND BASVURU_SKORU > 50
        ORDER BY BASVURU_SKORU DESC
    ) THEN 'Hak Kazandýnýz'
    WHEN YAS_GRUBU = 'GENÇ' AND BASVURU_SKORU > 50 THEN 'Yetersiz Kontenjan'
    ELSE 'Þartlar Saðlanmadý'
END AS Özel_Genç_Tarifesi
FROM VmAboneBasvuruDetay V
INNER JOIN ABONE A ON V.TC_NO = A.TC_KIMLIK_NO
INNER JOIN MESLEK M ON A.MESLEK_ID = M.MESLEK_ID;


